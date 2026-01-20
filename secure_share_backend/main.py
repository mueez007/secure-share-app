from fastapi import FastAPI, HTTPException, Depends, status, UploadFile, File, Form, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from typing import Optional, List
import uuid
import json
from datetime import datetime, timedelta
import os
from pathlib import Path
import hashlib
import asyncio

from config import settings
from database import get_db, init_db
from models import Content, PIN, AccessSession, TrustedDevice, SuspiciousActivity, DestructionCertificate
from security import SecurityUtils
from utils import FileUtils, ContentUtils, TimeUtils

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.PROJECT_VERSION,
)

# Create uploads directory (temporary for development)
uploads_dir = Path("uploads")
uploads_dir.mkdir(exist_ok=True)

# Mount static files for uploaded content
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize database
@app.on_event("startup")
def on_startup():
    init_db()
    print("✅ Database initialized")

# Health check
@app.get("/")
async def root():
    return {"message": "SecureShare Backend API", "status": "running", "version": settings.PROJECT_VERSION}

# ========== ZERO-KNOWLEDGE CONTENT UPLOAD ==========
@app.post("/content/upload")
async def upload_content(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    iv: str = Form(...),
    access_mode: str = Form(...),
    device_limit: int = Form(1),
    content_type: str = Form("text"),
    auto_terminate: bool = Form(True),
    require_biometric: bool = Form(False),
    dynamic_pin: bool = Form(False),
    duration_minutes: Optional[int] = Form(None),
    file_name: Optional[str] = Form(None),
    file_size: Optional[int] = Form(None),
    mime_type: Optional[str] = Form(None),
    pin_rotation_minutes: Optional[int] = Form(None),
    trusted_devices: Optional[str] = Form(None),
    # CLIENT PROVIDES PIN (generated locally in Flutter)
    pin: str = Form(...),
    # CLIENT PROVIDES key hash (for verification, not the key itself)
    key_hash: str = Form(...),
    db: Session = Depends(get_db),
):
    """
    Upload encrypted content with ZERO-KNOWLEDGE encryption.
    Backend NEVER sees encryption keys, only stores:
    - Encrypted file
    - PIN hash (for verification)
    - Key hash (for verification)
    - Metadata
    """
    try:
        # Validate inputs
        if not ContentUtils.validate_content_type(content_type):
            raise HTTPException(status_code=400, detail="Invalid content type")
        
        if access_mode not in ["time_based", "one_time"]:
            raise HTTPException(status_code=400, detail="Invalid access mode")
        
        # Validate PIN (client provides 4-digit PIN)
        if not pin or len(pin) != 4 or not pin.isdigit():
            raise HTTPException(status_code=400, detail="PIN must be 4 digits")
        
        # Generate content ID
        content_id = str(uuid.uuid4())
        
        # Save encrypted file (backend cannot read it)
        file_url = await FileUtils.save_uploaded_file(file, content_id)
        
        # Calculate expiry time
        expires_at = None
        if access_mode == "time_based" and duration_minutes:
            expires_at = SecurityUtils.calculate_expiry_time(duration_minutes)
        
        # Create content record - ZERO-KNOWLEDGE
        content = Content(
            id=content_id,
            content_key_hash=key_hash,  # ONLY STORE HASH, NEVER THE KEY
            iv=iv,
            encrypted_data_url=file_url,
            content_type=content_type,
            file_name=file_name or file.filename,
            file_size=file_size or 0,
            mime_type=mime_type or file.content_type,
            access_mode=access_mode,
            expires_at=expires_at,
            max_devices=device_limit,
            current_devices=0,
            dynamic_pin=dynamic_pin,
            pin_rotation_minutes=pin_rotation_minutes if dynamic_pin else None,
            auto_terminate=auto_terminate,
            require_biometric=require_biometric,
            screenshot_protection=True,
            watermarking=False,
            status="active"
        )
        
        # Hash the PIN (backend stores only hash for verification)
        pin_hash = SecurityUtils.hash_pin(pin)
        
        # Create PIN record
        pin_record = PIN(
            content_id=content_id,
            pin_hash=pin_hash,
            pin_value=SecurityUtils.encrypt_key_for_storage(pin),  # Encrypted at rest
            is_active=True,
            expires_at=expires_at,
            rotation_schedule={
                "interval_minutes": pin_rotation_minutes,
                "next_rotation": (datetime.utcnow() + timedelta(minutes=pin_rotation_minutes)).isoformat() 
                if dynamic_pin and pin_rotation_minutes else None
            } if dynamic_pin else None
        )
        
        # Add trusted devices if provided
        if trusted_devices:
            try:
                devices = json.loads(trusted_devices)
                for device_fp in devices:
                    trusted_device = TrustedDevice(
                        content_id=content_id,
                        device_fingerprint=device_fp
                    )
                    db.add(trusted_device)
            except:
                pass
        
        # Save to database
        db.add(content)
        db.add(pin_record)
        db.commit()
        db.refresh(content)
        
        # Schedule cleanup if time-based
        if expires_at:
            background_tasks.add_task(
                cleanup_expired_content,
                content_id,
                db
            )
        
        # Return success - backend NEVER returns encryption keys
        return {
            "content_id": content_id,
            "iv": iv,
            "expiry_time": expires_at.isoformat() if expires_at else None,
            "access_mode": access_mode,
            "device_limit": device_limit,
            "dynamic_pin": dynamic_pin,
            "auto_terminate": auto_terminate,
            "message": "Content uploaded with zero-knowledge encryption"
        }
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        print(f"Upload error: {e}")
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

# ========== ZERO-KNOWLEDGE CONTENT ACCESS ==========
@app.post("/content/access/{pin}")
async def access_content(
    pin: str,
    device_info: dict,
    db: Session = Depends(get_db),
):
    """
    Access content using PIN.
    Backend verifies PIN hash and key hash, but NEVER sees actual keys.
    Returns encrypted file URL for client-side decryption.
    """
    try:
        # Find active PIN
        pin_record = db.query(PIN).filter(
            PIN.pin_value == SecurityUtils.encrypt_key_for_storage(pin),
            PIN.is_active == True
        ).first()
        
        if not pin_record:
            # Try verifying via hash (for backward compatibility)
            all_pins = db.query(PIN).filter(PIN.is_active == True).all()
            for p in all_pins:
                if SecurityUtils.verify_pin(pin, p.pin_hash):
                    pin_record = p
                    break
        
        if not pin_record:
            raise HTTPException(status_code=404, detail="PIN not found")
        
        # Check if PIN is locked
        if pin_record.is_locked():
            raise HTTPException(status_code=423, detail="PIN locked due to too many attempts")
        
        # Get content
        content = db.query(Content).filter(Content.id == pin_record.content_id).first()
        if not content:
            raise HTTPException(status_code=404, detail="Content not found")
        
        # Check content status
        if content.status != "active":
            raise HTTPException(status_code=410, detail=f"Content is {content.status}")
        
        # Check if expired
        if SecurityUtils.is_expired(content.expires_at):
            content.status = "expired"
            db.commit()
            raise HTTPException(status_code=410, detail="Content expired")
        
        # Check device limit
        device_fingerprint = device_info.get("device_fingerprint", "")
        if content.current_devices >= content.max_devices:
            # Check if this device already has access
            existing_session = db.query(AccessSession).filter(
                AccessSession.content_id == content.id,
                AccessSession.device_fingerprint == device_fingerprint,
                AccessSession.is_active == True
            ).first()
            
            if not existing_session:
                raise HTTPException(status_code=403, detail="Device limit reached")
        
        # Check if biometric is required
        if content.require_biometric and not device_info.get("biometric_verified", False):
            raise HTTPException(status_code=403, detail="Biometric verification required")
        
        # Create or update access session
        session = db.query(AccessSession).filter(
            AccessSession.content_id == content.id,
            AccessSession.device_fingerprint == device_fingerprint
        ).first()
        
        if not session:
            # Create new session
            session_token = SecurityUtils.generate_session_token()
            session = AccessSession(
                id=str(uuid.uuid4()),
                content_id=content.id,
                device_id=device_info.get("device_id", ""),
                device_fingerprint=device_fingerprint,
                session_token=session_token,
                ip_address=device_info.get("ip_address"),
                user_agent=device_info.get("user_agent")
            )
            db.add(session)
            content.current_devices += 1
        else:
            session.update_activity()
            session_token = session.session_token
        
        # Increment view count
        content.views_count += 1
        session.view_count += 1
        
        # Handle one-time view
        if content.access_mode == "one_time":
            # Mark as viewed and schedule destruction
            content.status = "viewed"
            background_tasks.add_task(
                destroy_content,
                content.id,
                "viewed",
                db
            )
        
        # Reset PIN failed attempts on successful access
        pin_record.failed_attempts = 0
        pin_record.locked_until = None
        
        db.commit()
        
        # Return metadata and encrypted file URL
        # Client will decrypt locally with their own key
        return {
            "content_id": content.id,
            "access_granted": True,
            "session_token": session_token,
            "content_type": content.content_type,
            "file_name": content.file_name,
            "file_size": content.file_size,
            "mime_type": content.mime_type,
            "access_mode": content.access_mode,
            "expiry_time": content.expires_at.isoformat() if content.expires_at else None,
            "views_remaining": max(0, content.max_devices - content.current_devices),
            "current_views": content.views_count,
            # Return URL to encrypted file for streaming
            "encrypted_content_url": FileUtils.get_file_url(content.encrypted_data_url),
            "iv": content.iv,
            "security": {
                "auto_terminate": content.auto_terminate,
                "screenshot_protection": content.screenshot_protection,
                "watermarking": content.watermarking
            }
        }
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Access error: {e}")
        raise HTTPException(status_code=500, detail=f"Access failed: {str(e)}")

# ========== SECURITY ENDPOINTS ==========
@app.post("/security/report")
async def report_suspicious_activity(
    report: dict,
    db: Session = Depends(get_db),
):
    """Report suspicious activity"""
    try:
        content_id = report.get("content_id")
        activity_type = report.get("activity_type")
        device_id = report.get("device_id")
        description = report.get("description", "")
        
        if not content_id or not activity_type:
            raise HTTPException(status_code=400, detail="Missing required fields")
        
        # Create suspicious activity record
        activity = SuspiciousActivity(
            content_id=content_id,
            activity_type=activity_type,
            device_id=device_id,
            description=description
        )
        db.add(activity)
        
        # Check if content should be terminated
        content = db.query(Content).filter(Content.id == content_id).first()
        if content and content.auto_terminate:
            # Check activity pattern
            recent_activities = db.query(SuspiciousActivity).filter(
                SuspiciousActivity.content_id == content_id,
                SuspiciousActivity.detected_at >= datetime.utcnow() - timedelta(minutes=5)
            ).count()
            
            if recent_activities >= 3:
                content.status = "terminated"
                background_tasks.add_task(
                    destroy_content,
                    content_id,
                    "suspicious_activity",
                    db
                )
        
        db.commit()
        
        return {"message": "Activity reported", "content_status": content.status if content else "unknown"}
        
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Failed to report activity: {str(e)}")

@app.post("/content/{content_id}/terminate")
async def terminate_content(
    content_id: str,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    """Manually terminate content"""
    content = db.query(Content).filter(Content.id == content_id).first()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    if content.status in ["terminated", "expired", "viewed"]:
        raise HTTPException(status_code=400, detail=f"Content already {content.status}")
    
    content.status = "terminated"
    db.commit()
    
    # Schedule destruction
    background_tasks.add_task(
        destroy_content,
        content_id,
        "manual_termination",
        db
    )
    
    return {"message": "Content terminated", "content_id": content_id}

# ========== CONTENT STREAMING ==========
@app.get("/content/stream/{content_id}")
async def stream_content(
    content_id: str,
    session_token: str,
    db: Session = Depends(get_db),
):
    """Stream encrypted content (for secure viewing)"""
    # Verify session
    session = db.query(AccessSession).filter(
        AccessSession.content_id == content_id,
        AccessSession.session_token == session_token,
        AccessSession.is_active == True
    ).first()
    
    if not session:
        raise HTTPException(status_code=401, detail="Invalid or expired session")
    
    content = db.query(Content).filter(Content.id == content_id).first()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    # Check content status
    if content.status != "active":
        raise HTTPException(status_code=410, detail=f"Content is {content.status}")
    
    # Update session activity
    session.update_activity()
    db.commit()
    
    # Return encrypted file (client decrypts locally)
    file_path = content.encrypted_data_url
    if file_path.startswith("/uploads/"):
        file_path = file_path[1:]
    
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(
        file_path,
        media_type=content.mime_type or "application/octet-stream",
        headers={
            "X-Content-Type-Options": "nosniff",
            "Content-Disposition": f'inline; filename="{content.file_name}"'
        }
    )

# ========== BACKGROUND TASKS ==========
async def cleanup_expired_content(content_id: str, db: Session):
    """Cleanup expired content"""
    await asyncio.sleep(60)  # Wait 1 minute after expiry
    
    content = db.query(Content).filter(Content.id == content_id).first()
    if content and content.status == "active" and SecurityUtils.is_expired(content.expires_at):
        content.status = "expired"
        db.commit()
        
        # Destroy content after expiry
        await destroy_content(content_id, "expired", db)

async def destroy_content(content_id: str, reason: str, db: Session):
    """Destroy content completely"""
    try:
        # Get content
        content = db.query(Content).filter(Content.id == content_id).first()
        if not content:
            return
        
        # Delete file from storage
        FileUtils.delete_file(content.encrypted_data_url)
        
        # Generate destruction certificate
        certificate = DestructionCertificate(
            id=str(uuid.uuid4()),
            content_id=content_id,
            reason=reason,
            proof_hash=SecurityUtils.generate_proof_of_destruction(content_id, reason)["proof_hash"],
            signature=SecurityUtils.generate_proof_of_destruction(content_id, reason)["signature"],
            metadata={
                "content_type": content.content_type,
                "file_name": content.file_name,
                "destroyed_at": datetime.utcnow().isoformat()
            }
        )
        
        # Delete all related records
        db.query(PIN).filter(PIN.content_id == content_id).delete()
        db.query(AccessSession).filter(AccessSession.content_id == content_id).delete()
        db.query(TrustedDevice).filter(TrustedDevice.content_id == content_id).delete()
        db.query(SuspiciousActivity).filter(SuspiciousActivity.content_id == content_id).delete()
        
        # Delete content record
        db.delete(content)
        
        # Add destruction certificate
        db.add(certificate)
        
        db.commit()
        
        print(f"✅ Content {content_id} destroyed ({reason})")
        
    except Exception as e:
        db.rollback()
        print(f"❌ Error destroying content {content_id}: {e}")

# ========== ANALYTICS ==========
@app.get("/content/{content_id}/analytics")
async def get_content_analytics(
    content_id: str,
    db: Session = Depends(get_db),
):
    """Get content analytics"""
    content = db.query(Content).filter(Content.id == content_id).first()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    # Get active sessions
    active_sessions = db.query(AccessSession).filter(
        AccessSession.content_id == content_id,
        AccessSession.is_active == True
    ).all()
    
    return {
        "content_info": content.to_dict(),
        "analytics": {
            "total_views": content.views_count,
            "active_sessions": len(active_sessions),
            "active_devices": [
                {
                    "device_id": session.device_id,
                    "last_activity": session.last_activity.isoformat(),
                    "view_count": session.view_count
                }
                for session in active_sessions
            ]
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )