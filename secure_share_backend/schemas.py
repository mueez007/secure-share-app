from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum

class AccessMode(str, Enum):
    TIME_BASED = "time_based"
    ONE_TIME = "one_time"

class ContentType(str, Enum):
    TEXT = "text"
    IMAGE = "image"
    PDF = "pdf"
    VIDEO = "video"
    AUDIO = "audio"
    DOCUMENT = "document"

class ContentStatus(str, Enum):
    ACTIVE = "active"
    PAUSED = "paused"
    TERMINATED = "terminated"
    EXPIRED = "expired"
    VIEWED = "viewed"

class ContentUpload(BaseModel):
    iv: str = Field(..., description="Initialization vector for encryption")
    access_mode: AccessMode
    device_limit: int = Field(1, ge=1, le=10)
    content_type: ContentType
    auto_terminate: bool = True
    require_biometric: bool = False
    dynamic_pin: bool = False
    duration_minutes: Optional[int] = Field(None, ge=1, le=525600)  # Max 1 year
    file_name: Optional[str] = None
    file_size: Optional[int] = None
    mime_type: Optional[str] = None
    pin_rotation_minutes: Optional[int] = Field(None, ge=1, le=1440)  # Max 1 day
    trusted_devices: Optional[List[str]] = None

    @validator('duration_minutes')
    def validate_duration(cls, v, values):
        if values.get('access_mode') == AccessMode.TIME_BASED and v is None:
            raise ValueError('duration_minutes is required for time_based access mode')
        return v

    @validator('pin_rotation_minutes')
    def validate_pin_rotation(cls, v, values):
        if values.get('dynamic_pin') and v is None:
            raise ValueError('pin_rotation_minutes is required when dynamic_pin is enabled')
        return v

class ContentAccess(BaseModel):
    device_id: str
    device_fingerprint: str
    biometric_verified: bool = False
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None

class SuspiciousActivityReport(BaseModel):
    content_id: str
    activity_type: str
    device_id: str
    description: Optional[str] = None

class ContentResponse(BaseModel):
    content_id: str
    pin: str
    iv: str
    expiry_time: Optional[str] = None
    access_mode: str
    device_limit: int
    dynamic_pin: bool
    auto_terminate: bool
    message: str

class AccessResponse(BaseModel):
    content_id: str
    access_granted: bool
    session_token: str
    content_type: str
    file_name: str
    file_size: int
    mime_type: str
    access_mode: str
    expiry_time: Optional[str] = None
    views_remaining: int
    current_views: int
    encrypted_content_url: str
    iv: str
    security: Dict[str, Any]

class AnalyticsResponse(BaseModel):
    content_info: Dict[str, Any]
    analytics: Dict[str, Any]

class DestructionProof(BaseModel):
    certificate_id: str
    content_id: str
    reason: str
    destroyed_at: str
    proof_hash: str
    signature: str
    metadata: Dict[str, Any]