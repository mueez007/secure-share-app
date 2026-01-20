from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import Optional, Dict, List
import secrets
from datetime import datetime, timedelta
import uuid
from fastapi.middleware.cors import CORSMiddleware
import asyncio

app = FastAPI(title="Secure Share Backend")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For development only
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory storage (replace with database later)
content_store: Dict[str, dict] = {}
# Track used PINs to avoid collisions
used_pins = set()

class UploadRequest(BaseModel):
    encrypted_content: str
    iv: str  # Add IV field for Zero-Knowledge encryption
    access_mode: str  # "time_based" or "one_time"
    duration_minutes: Optional[int] = None
    device_limit: int = 1

class AccessRequest(BaseModel):
    pin: str
    device_id: Optional[str] = None

class TerminateRequest(BaseModel):
    pin: str

# Background task to clean up expired content
async def cleanup_expired_content():
    while True:
        await asyncio.sleep(60)  # Check every minute
        current_time = datetime.utcnow()
        expired_pins = []
        
        for pin, content in content_store.items():
            if (content["access_mode"] == "time_based" and 
                content["expiry_time"] and 
                current_time > content["expiry_time"]):
                expired_pins.append(pin)
        
        for pin in expired_pins:
            del content_store[pin]
            if pin in used_pins:
                used_pins.remove(pin)
        
        if expired_pins:
            print(f"Cleaned up {len(expired_pins)} expired content items")

# Start cleanup task on startup
@app.on_event("startup")
async def startup_event():
    asyncio.create_task(cleanup_expired_content())

@app.post("/upload")
async def upload_content(request: UploadRequest):
    """Upload encrypted content and get a PIN"""
    
    # Generate unique 4-digit PIN (avoid collisions)
    for _ in range(10):  # Try up to 10 times
        pin = str(secrets.randbelow(9000) + 1000)  # 1000-9999
        if pin not in used_pins:
            break
    else:
        # Fallback to longer PIN if 4-digits are exhausted (unlikely for MVP)
        pin = str(secrets.randbelow(90000) + 10000)
    
    used_pins.add(pin)
    
    # Generate unique content ID
    content_id = str(uuid.uuid4())
    
    # Calculate expiry
    expiry_time = None
    if request.access_mode == "time_based" and request.duration_minutes:
        expiry_time = datetime.utcnow() + timedelta(minutes=request.duration_minutes)
    
    # Store content
    content_store[pin] = {
        "content_id": content_id,
        "encrypted_content": request.encrypted_content,
        "iv": request.iv,  # Store the IV
        "access_mode": request.access_mode,
        "expiry_time": expiry_time,
        "device_limit": request.device_limit,
        "views": 0,
        "devices_accessed": [],
        "created_at": datetime.utcnow(),
        "last_accessed": None
    }
    
    return {
        "success": True,
        "pin": pin,
        "content_id": content_id,
        "expiry_time": expiry_time,
        "message": f"Content uploaded successfully. PIN: {pin}"
    }

@app.post("/access/{pin}")
async def access_content(pin: str, request: AccessRequest):
    """Access content with PIN"""
    
    # PIN must match exactly
    if pin != request.pin:
        raise HTTPException(status_code=401, detail="PIN mismatch")
    
    if pin not in content_store:
        raise HTTPException(status_code=404, detail="PIN not found or content expired")
    
    content = content_store[pin]
    
    # Check expiry
    if (content["access_mode"] == "time_based" and 
        content["expiry_time"] and 
        datetime.utcnow() > content["expiry_time"]):
        # Clean up expired content
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)
        raise HTTPException(status_code=410, detail="Content expired")
    
    # Check if one-time view already used
    if content["access_mode"] == "one_time" and content["views"] > 0:
        # Clean up one-time content after viewing
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)
        raise HTTPException(status_code=410, detail="Content already viewed and deleted")
    
    # Check device limit
    if content["views"] >= content["device_limit"]:
        # Allow existing devices to re-access if tracked
        if request.device_id and request.device_id in content["devices_accessed"]:
            pass 
        else:
            raise HTTPException(status_code=403, detail="Device limit reached")
    
    # Track device if provided
    if request.device_id and request.device_id not in content["devices_accessed"]:
        content["devices_accessed"].append(request.device_id)
        # Increment views only for new devices
        content["views"] += 1
    elif not request.device_id:
         # If no device ID provided, always increment
         content["views"] += 1

    content["last_accessed"] = datetime.utcnow()
    
    # If one-time view and this is the first view, mark for deletion after return
    if content["access_mode"] == "one_time" and content["views"] == 1:
        # Schedule deletion after a short delay
        asyncio.create_task(delete_one_time_content(pin))
    
    return {
        "success": True,
        "encrypted_content": content["encrypted_content"],
        "iv": content.get("iv", ""), # Return IV for decryption
        "views_remaining": max(0, content["device_limit"] - content["views"]),
        "expiry_time": content["expiry_time"],
        "access_mode": content["access_mode"]
    }

async def delete_one_time_content(pin: str):
    """Delete one-time content after a short delay"""
    await asyncio.sleep(5)  # Give 5 seconds for client to receive response
    if pin in content_store:
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)

@app.get("/status/{pin}")
async def get_status(pin: str):
    """Get content status"""
    if pin not in content_store:
        raise HTTPException(status_code=404, detail="PIN not found")
    
    content = content_store[pin]
    
    # Check expiry
    if (content["access_mode"] == "time_based" and 
        content["expiry_time"] and 
        datetime.utcnow() > content["expiry_time"]):
        # Clean up expired content
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)
        raise HTTPException(status_code=410, detail="Content expired")
    
    return {
        "success": True,
        "access_mode": content["access_mode"],
        "views": content["views"],
        "device_limit": content["device_limit"],
        "expiry_time": content["expiry_time"],
        "created_at": content["created_at"],
        "last_accessed": content["last_accessed"],
        "devices_accessed": len(content["devices_accessed"]),
        "is_active": True
    }

@app.delete("/terminate/{pin}")
async def terminate_content(pin: str):
    """Terminate content immediately"""
    if pin in content_store:
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)
        return {
            "success": True,
            "message": "Content terminated successfully"
        }
    raise HTTPException(status_code=404, detail="PIN not found")

@app.post("/terminate")
async def terminate_content_post(request: TerminateRequest):
    """Terminate content with PIN in request body"""
    pin = request.pin
    if pin in content_store:
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)
        return {
            "success": True,
            "message": "Content terminated successfully"
        }
    raise HTTPException(status_code=404, detail="PIN not found")

@app.get("/stats")
async def get_stats():
    """Get server statistics"""
    total_content = len(content_store)
    time_based_count = sum(1 for c in content_store.values() if c["access_mode"] == "time_based")
    one_time_count = sum(1 for c in content_store.values() if c["access_mode"] == "one_time")
    total_views = sum(c["views"] for c in content_store.values())
    
    return {
        "success": True,
        "total_active_content": total_content,
        "time_based_content": time_based_count,
        "one_time_content": one_time_count,
        "total_views": total_views,
        "server_time": datetime.utcnow().isoformat()
    }

@app.get("/cleanup")
async def manual_cleanup():
    """Manually trigger cleanup of expired content"""
    current_time = datetime.utcnow()
    expired_pins = []
    
    for pin, content in content_store.items():
        if (content["access_mode"] == "time_based" and 
            content["expiry_time"] and 
            current_time > content["expiry_time"]):
            expired_pins.append(pin)
    
    for pin in expired_pins:
        del content_store[pin]
        if pin in used_pins:
            used_pins.remove(pin)
    
    return {
        "success": True,
        "cleaned_up": len(expired_pins),
        "remaining_content": len(content_store)
    }

@app.get("/")
async def root():
    return {
        "message": "Secure Share Backend API",
        "version": "1.0.0",
        "endpoints": [
            "POST /upload - Upload encrypted content",
            "POST /access/{pin} - Access content with PIN",
            "GET /status/{pin} - Get content status",
            "DELETE /terminate/{pin} - Terminate content",
            "GET /stats - Get server statistics",
            "GET /cleanup - Manual cleanup"
        ]
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)