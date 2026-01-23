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
import base64
# Import your modules
from config import settings
from database import get_db, init_db
from models import Content, PIN, AccessSession
from security import SecurityUtils
from utils import FileUtils, ContentUtils, TimeUtils  # ADD ContentUtils and TimeUtils

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

# Helper function for time calculations
def _calculate_seconds_until(expiry_time):
    """Calculate seconds until expiry (simple version)"""
    return TimeUtils.seconds_until(expiry_time)  # Use TimeUtils

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

# ========== CONTENT UPLOAD ENDPOINT ========== (FIXED)
@app.post("/content/upload")
async def upload_content(
    file: UploadFile = File(...),
    iv: str = Form(...),
    access_mode: str = Form(...),
    device_limit: int = Form(1),
    content_type: str = Form("text"),  # Client-specified type
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
        print(f"📤 Upload request: {file.filename}, Client type: {content_type}, PIN: {pin}")
        
        # Validate PIN (client provides 4-digit PIN)
        if not pin or len(pin) != 4 or not pin.isdigit():
            raise HTTPException(status_code=400, detail="PIN must be 4 digits")
        
        # Validate content type
        if not ContentUtils.validate_content_type(content_type):
            raise HTTPException(status_code=400, detail=f"Invalid content type: {content_type}")
        
        # Generate content ID
        content_id = str(uuid.uuid4())
        
        # Save encrypted file (backend cannot read it)
        file_url = await FileUtils.save_uploaded_file(file, content_id)
        print(f"✅ File saved: {file_url}")
        
        # Calculate expiry time
        expires_at = None
        if access_mode == "time_based" and duration_minutes:
            expires_at = datetime.utcnow() + timedelta(minutes=duration_minutes)
            print(f"📅 Content expiry set to: {expires_at.isoformat()}")
            print(f"⏰ That's {duration_minutes} minutes from now")
        
        # Get file metadata
        actual_file_name = file_name or file.filename or "encrypted_file"
        actual_file_size = file_size or 0
        
        # Get MIME type - prefer provided, fallback to detected
        actual_mime_type = mime_type or file.content_type
        if not actual_mime_type and file.filename:
            actual_mime_type = ContentUtils.get_mime_type(file.filename)
        
        # If client says it's text but no MIME type, set it
        if content_type == "text" and not actual_mime_type:
            actual_mime_type = "text/plain"
        
        # Create content record - ZERO-KNOWLEDGE (only stores key hash)
        content = Content(
            id=content_id,
            content_key_hash=key_hash,  # Only store hash, never the key
            iv=iv,
            encrypted_data_url=file_url,
            content_type=content_type,  # Use client-specified type
            file_name=actual_file_name,
            file_size=actual_file_size,
            mime_type=actual_mime_type,
            access_mode=access_mode,
            expires_at=expires_at,
            max_devices=device_limit,
            current_devices=0,  # Initialize to 0
            dynamic_pin=dynamic_pin,
            pin_rotation_minutes=pin_rotation_minutes if dynamic_pin else None,
            auto_terminate=auto_terminate,
            require_biometric=require_biometric,
            status="active",
            views_count=0  # Explicitly initialize
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
            failed_attempts=0,  # Initialize
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
        
        print(f"✅ Content uploaded: {content_id}, Type: {content_type}, Expires: {expires_at}")
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

# ========== CONTENT ACCESS ENDPOINT ========== (FIXED)
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
        
        # Handle one-time view
        if content.access_mode == "one_time" and content.views_count > 0:
            content.status = "viewed"
            db.commit()
            raise HTTPException(status_code=410, detail="Content already viewed (one-time view)")
        
        # Check if expired
        if content.expires_at:
            now = datetime.utcnow()
            if now > content.expires_at:
                content.status = "expired"
                db.commit()
                raise HTTPException(status_code=410, detail="Content expired")
            else:
                # Debug log
                time_left = content.expires_at - now
                print(f"⏰ Content expires in: {TimeUtils.format_time_remaining(content.expires_at)}")
        
        # Device limit check
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
                user_agent=device_info.get("user_agent"),
                view_count=0  # Initialize to 0
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
        
        # Increment view count with null safety
        content.views_count = (content.views_count or 0) + 1
        session.view_count = (session.view_count or 0) + 1
        
        # Reset PIN failed attempts on successful access
        pin_record.failed_attempts = 0
        pin_record.locked_until = None
        
        db.commit()
        
        print(f"✅ Access granted: {content.id}, Type: {content.content_type}, Views: {content.views_count}, Devices: {content.current_devices}/{content.max_devices}")
        
        # Calculate views remaining
        views_remaining = max(0, content.max_devices - content.current_devices)
        
        # Get streaming URL
        encrypted_content_url = FileUtils.get_file_url(content.encrypted_data_url)
        encrypted_text_content = ""
        
        # Handle text content differently
        if content.content_type == "text":
            try:
                file_path = content.encrypted_data_url
                if file_path.startswith("/uploads/"):
                    file_path = file_path[1:]  # Remove leading slash
                
                print(f"📄 Looking for text file at: {file_path}")
                
                if os.path.exists(file_path):
                    with open(file_path, 'rb') as f:
                        file_bytes = f.read()
                    encrypted_text_content = base64.b64encode(file_bytes).decode('utf-8')
                    print(f"✅ Read encrypted text: {len(file_bytes)} bytes")
                else:
                    print(f"❌ Text file not found: {file_path}")
            except Exception as e:
                print(f"❌ Error reading text content: {e}")
        
        # Return metadata
        return {
            "content_id": content.id,
            "access_granted": True,
            "session_token": session_token,
            "content_type": content.content_type,  # image, pdf, video, audio, text, document
            "file_name": content.file_name,
            "file_size": content.file_size or 0,
            "mime_type": content.mime_type,
            "access_mode": content.access_mode,
            "expiry_time": content.expires_at.isoformat() if content.expires_at else None,
            "remaining_time_seconds": _calculate_seconds_until(content.expires_at),
            "remaining_time_formatted": TimeUtils.format_time_remaining(content.expires_at),
            "views_remaining": views_remaining,
            "device_limit": content.max_devices,
            "current_devices": content.current_devices,
            "current_views": content.views_count,
            # For text: return encrypted text, for others: return streaming URL
            "encrypted_content": encrypted_text_content if content.content_type == "text" else "",
            "encrypted_content_url": encrypted_content_url if content.content_type != "text" else "",
            "streaming_url": f"http://127.0.0.1:8000/content/stream/{content.id}?session_token={session_token}",
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
        raise HTTPException(status_code=500, detail=f"Access failed: {str(e)}")

# ========== STREAM CONTENT ENDPOINT ========== (FIXED)
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
        
        # Check if content is still accessible
        if content.status != "active":
            raise HTTPException(status_code=410, detail=f"Content is {content.status}")
        
        # Update session activity
        session.last_activity = datetime.utcnow()
        session.view_count = (session.view_count or 0) + 1
        db.commit()
        
        # Get file path
        file_path = content.encrypted_data_url
        if file_path.startswith("/uploads/"):
            file_path = file_path[1:]
        
        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="File not found")
        
        print(f"📥 Streaming: {content_id} ({content.content_type}) to session {session_token[:10]}...")
        
        # Determine media type
        media_type = content.mime_type or "application/octet-stream"
        
        return FileResponse(
            file_path,
            media_type=media_type,
            headers={
                "X-Content-Type-Options": "nosniff",
                "Content-Disposition": f'inline; filename="{content.file_name}"',
                "Cache-Control": "no-store, no-cache, must-revalidate",
                "Pragma": "no-cache",
                "Expires": "0"
            }
        )
        
    except Exception as e:
        print(f"❌ Stream error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Stream failed: {str(e)}")

# ========== CONTENT MANAGEMENT ENDPOINTS ==========
@app.post("/content/{content_id}/terminate")
async def terminate_content(
    content_id: str,
    db: Session = Depends(get_db),
):
    """Terminate content immediately"""
    content = db.query(Content).filter(Content.id == content_id).first()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    content.status = "terminated"
    
    # Also deactivate PIN
    pin = db.query(PIN).filter(PIN.content_id == content_id).first()
    if pin:
        pin.is_active = False
    
    db.commit()
    
    # Try to delete file
    try:
        file_path = content.encrypted_data_url
        if file_path.startswith("/uploads/"):
            file_path = file_path[1:]
        if os.path.exists(file_path):
            os.remove(file_path)
            print(f"🗑️ Deleted file: {file_path}")
    except Exception as e:
        print(f"⚠️ Could not delete file: {e}")
    
    return {"message": "Content terminated", "content_id": content_id}

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
                "mime": c.mime_type,
                "filename": c.file_name,
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
                "active": p.is_active,
                "attempts": p.failed_attempts
            }
            for p in pins
        ]
    }

@app.get("/debug/files")
async def debug_files():
    """List all files in uploads directory"""
    upload_dir = Path("uploads")
    if not upload_dir.exists():
        return {"files": [], "count": 0}
    
    files = []
    for file_path in upload_dir.glob("*"):
        files.append({
            "name": file_path.name,
            "size": file_path.stat().st_size,
            "modified": datetime.fromtimestamp(file_path.stat().st_mtime).isoformat()
        })
    
    return {"files": files, "count": len(files)}

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