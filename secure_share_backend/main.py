from fastapi import FastAPI, HTTPException, Depends, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
import uuid
import json
from datetime import datetime, timedelta
import os
from pathlib import Path

# Import your modules
from config import settings
from database import get_db, init_db
from models import Content, PIN, AccessSession
from security import SecurityUtils
from utils import FileUtils

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.PROJECT_VERSION,
)

# Create uploads directory
uploads_dir = Path("uploads")
uploads_dir.mkdir(exist_ok=True)

# Mount static files for uploaded content
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for testing
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize database on startup
@app.on_event("startup")
def on_startup():
    init_db()
    print("✅ Database initialized")
    print(f"🔐 Using SECRET_KEY: {settings.SECRET_KEY[:20]}...")
    print(f"📁 Database: {settings.DATABASE_URL}")

# Health check endpoint
@app.get("/")
async def root():
    return {
        "message": "SecureShare Backend API", 
        "status": "running", 
        "version": settings.PROJECT_VERSION,
        "endpoints": {
            "upload": "POST /content/upload",
            "access": "POST /content/access/{pin}",
            "stream": "GET /content/stream/{content_id}?session_token={token}"
        }
    }

# ========== CONTENT UPLOAD ENDPOINT ==========
@app.post("/content/upload")
async def upload_content(
    file: UploadFile = File(...),
    iv: str = Form(...),
    access_mode: str = Form(...),
    device_limit: int = Form(1),
    content_type: str = Form("text"),
    auto_terminate: bool = Form(True),
    require_biometric: bool = Form(False),
    dynamic_pin: bool = Form(False),
    duration_minutes: int = Form(None),
    file_name: str = Form(None),
    file_size: int = Form(None),
    mime_type: str = Form(None),
    pin_rotation_minutes: int = Form(None),
    trusted_devices: str = Form(None),
    pin: str = Form(...),  # Client provides PIN
    key_hash: str = Form(...),  # Client provides key hash
    db: Session = Depends(get_db),
):
    """
    Upload encrypted content with zero-knowledge encryption.
    Backend never sees the encryption key, only stores its hash.
    """
    try:
        print(f"📤 Upload request: {file.filename}, Type: {content_type}, PIN: {pin}")
        
        # Validate PIN (client provides 4-digit PIN)
        if not pin or len(pin) != 4 or not pin.isdigit():
            raise HTTPException(status_code=400, detail="PIN must be 4 digits")
        
        # Generate content ID
        content_id = str(uuid.uuid4())
        
        # Save encrypted file (backend cannot read it)
        file_url = await FileUtils.save_uploaded_file(file, content_id)
        print(f"✅ File saved: {file_url}")
        
        # Calculate expiry time
        expires_at = None
        if access_mode == "time_based" and duration_minutes:
            expires_at = datetime.utcnow() + timedelta(minutes=duration_minutes)
        
        # Create content record - ZERO-KNOWLEDGE (only stores key hash)
        content = Content(
            id=content_id,
            content_key_hash=key_hash,  # Only store hash, never the key
            iv=iv,
            encrypted_data_url=file_url,
            content_type=content_type,
            file_name=file_name or file.filename,
            file_size=file_size or 0,
            mime_type=mime_type or file.content_type,
            access_mode=access_mode,
            expires_at=expires_at,
            max_devices=device_limit,
            current_devices=0,  # Initialize to 0
            dynamic_pin=dynamic_pin,
            pin_rotation_minutes=pin_rotation_minutes if dynamic_pin else None,
            auto_terminate=auto_terminate,
            require_biometric=require_biometric,
            status="active"
        )
        
        # Hash the PIN (backend stores only hash for verification)
        pin_hash = SecurityUtils.hash_pin(pin)
        print(f"🔒 PIN hash created: {pin_hash[:30]}...")
        
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
        
        # Save to database
        db.add(content)
        db.add(pin_record)
        db.commit()
        db.refresh(content)
        
        print(f"✅ Content uploaded: {content_id}, Expires: {expires_at}")
        print(f"📌 PIN stored in database for content: {content_id}")
        
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
        print(f"❌ Upload error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

# ========== CONTENT ACCESS ENDPOINT ========== (FIXED DEVICE LIMIT LOGIC)
@app.post("/content/access/{pin}")
async def access_content(
    pin: str,
    device_info: dict,
    db: Session = Depends(get_db),
):
    """
    Access content using PIN.
    Backend verifies PIN hash but NEVER sees encryption keys.
    Returns encrypted file URL for client-side decryption.
    """
    try:
        print(f"🔑 Access attempt with PIN: {pin}")
        
        # DEBUG: List all PINs in database
        all_pins = db.query(PIN).all()
        print(f"🔍 Database has {len(all_pins)} PIN records")
        
        # Find the correct PIN by checking ALL PIN hashes
        pin_record = None
        for p in all_pins:
            if SecurityUtils.verify_pin(pin, p.pin_hash) and p.is_active:
                pin_record = p
                print(f"✅ Found PIN match for {pin} with content: {p.content_id}")
                break
        
        if not pin_record:
            print(f"❌ No PIN found for {pin}")
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
        if content.expires_at and datetime.utcnow() > content.expires_at:
            content.status = "expired"
            db.commit()
            raise HTTPException(status_code=410, detail="Content expired")
        
        # ========== FIXED DEVICE LIMIT LOGIC ==========
        device_fingerprint = device_info.get("device_fingerprint", "")
        
        # Check if this device already has access
        existing_session = db.query(AccessSession).filter(
            AccessSession.content_id == content.id,
            AccessSession.device_fingerprint == device_fingerprint,
            AccessSession.is_active == True
        ).first()
        
        # If this is a NEW device and device limit is reached, block access
        if not existing_session and content.current_devices >= content.max_devices:
            print(f"❌ Device limit reached: {content.current_devices}/{content.max_devices}")
            raise HTTPException(status_code=403, detail="Device limit reached")
        
        # Create or update access session
        if not existing_session:
            # This is a NEW device
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
            
            # Increment device count for NEW device
            content.current_devices = content.current_devices + 1
            print(f"📱 New device added. Total devices: {content.current_devices}/{content.max_devices}")
        else:
            # Existing device - just update session
            session = existing_session
            session.update_activity()
            session_token = session.session_token
            print(f"📱 Existing device access: {device_fingerprint[:10]}...")
        
        # Check if biometric is required
        if content.require_biometric and not device_info.get("biometric_verified", False):
            raise HTTPException(status_code=403, detail="Biometric verification required")
        
        # Increment view count
        content.views_count = content.views_count + 1
        session.view_count = session.view_count + 1
        
        # Reset PIN failed attempts on successful access
        pin_record.failed_attempts = 0
        pin_record.locked_until = None
        
        db.commit()
        
        print(f"✅ Access granted: {content.id}, Views: {content.views_count}, Devices: {content.current_devices}/{content.max_devices}")
        
        # Calculate views remaining
        views_remaining = max(0, content.max_devices - content.current_devices)
        
        # Return metadata and encrypted file URL
        # Client will decrypt locally with their own key
        return {
            "content_id": content.id,
            "access_granted": True,
            "session_token": session_token,
            "content_type": content.content_type,
            "file_name": content.file_name,
            "file_size": content.file_size or 0,
            "mime_type": content.mime_type,
            "access_mode": content.access_mode,
            "expiry_time": content.expires_at.isoformat() if content.expires_at else None,
            "views_remaining": views_remaining,
            "device_limit": content.max_devices,
            "current_devices": content.current_devices,
            "current_views": content.views_count,
            # Return URL to encrypted file for streaming
            "encrypted_content_url": FileUtils.get_file_url(content.encrypted_data_url),
            "iv": content.iv,
            "security": {
                "auto_terminate": content.auto_terminate,
                "require_biometric": content.require_biometric
            }
        }
        
    except HTTPException as he:
        print(f"❌ Access error: {he.detail}")
        raise he
    except Exception as e:
        print(f"❌ Access failed: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Access failed: {str(e)}")

# ========== STREAM CONTENT ENDPOINT ==========
@app.get("/content/stream/{content_id}")
async def stream_content(
    content_id: str,
    session_token: str,
    db: Session = Depends(get_db),
):
    """Stream encrypted content (for secure viewing)"""
    try:
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
        
        # Update session activity
        session.last_activity = datetime.utcnow()
        db.commit()
        
        # Return encrypted file (client decrypts locally)
        file_path = content.encrypted_data_url
        if file_path.startswith("/uploads/"):
            file_path = file_path[1:]
        
        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="File not found")
        
        print(f"📥 Streaming: {content_id} to session {session_token[:10]}...")
        
        return FileResponse(
            file_path,
            media_type=content.mime_type or "application/octet-stream",
            headers={
                "X-Content-Type-Options": "nosniff",
                "Content-Disposition": f'inline; filename="{content.file_name}"'
            }
        )
        
    except Exception as e:
        print(f"❌ Stream error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Stream failed: {str(e)}")

# ========== DEBUG ENDPOINTS ==========
@app.get("/debug/content")
async def debug_content(db: Session = Depends(get_db)):
    """Debug endpoint to list all content"""
    contents = db.query(Content).all()
    pins = db.query(PIN).all()
    
    return {
        "content_count": len(contents),
        "pin_count": len(pins),
        "content": [
            {
                "id": c.id[:8] + "...",
                "type": c.content_type,
                "status": c.status,
                "views": c.views_count or 0,
                "devices": f"{c.current_devices or 0}/{c.max_devices}",
                "expires": c.expires_at.isoformat() if c.expires_at else None
            }
            for c in contents
        ],
        "pins": [
            {
                "content_id": p.content_id[:8] + "...",
                "pin_hash": p.pin_hash[:20] + "..."
            }
            for p in pins
        ]
    }

@app.get("/debug/db-check")
async def debug_db_check():
    """Check database connectivity"""
    try:
        init_db()
        return {"status": "Database initialized successfully"}
    except Exception as e:
        return {"status": "Database error", "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=8000,
        reload=True
    )