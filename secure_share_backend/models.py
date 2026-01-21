from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
from datetime import datetime, timedelta
import json

class Content(Base):
    __tablename__ = "content"
    
    id = Column(String, primary_key=True, index=True)
    content_key_hash = Column(String, nullable=False)  # Hash of content key (not the key itself)
    iv = Column(String, nullable=False)  # Initialization vector
    encrypted_data_url = Column(String, nullable=False)  # Cloud storage URL
    
    # Metadata
    content_type = Column(String, nullable=False)  # text, image, pdf, video, audio
    file_name = Column(String)
    file_size = Column(Integer)
    mime_type = Column(String)
    
    # Access control
    access_mode = Column(String, nullable=False)  # time_based, one_time
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True))
    max_devices = Column(Integer, default=1)
    current_devices = Column(Integer, default=0, nullable=False)  # FIXED: added nullable=False
    
    # Security settings
    dynamic_pin = Column(Boolean, default=False)
    pin_rotation_minutes = Column(Integer, nullable=True)
    auto_terminate = Column(Boolean, default=True)
    require_biometric = Column(Boolean, default=False)
    screenshot_protection = Column(Boolean, default=True)
    watermarking = Column(Boolean, default=False)
    
    # Status
    status = Column(String, default="active")  # active, paused, terminated, expired
    views_count = Column(Integer, default=0, nullable=False)  # FIXED: added nullable=False
    
    # Relationships
    pins = relationship("PIN", back_populates="content", cascade="all, delete-orphan")
    access_sessions = relationship("AccessSession", back_populates="content", cascade="all, delete-orphan")
    trusted_devices = relationship("TrustedDevice", back_populates="content", cascade="all, delete-orphan")
    suspicious_activities = relationship("SuspiciousActivity", back_populates="content", cascade="all, delete-orphan")
    
    def to_dict(self):
        return {
            "content_id": self.id,
            "content_type": self.content_type,
            "file_name": self.file_name,
            "file_size": self.file_size,
            "mime_type": self.mime_type,
            "access_mode": self.access_mode,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "expires_at": self.expires_at.isoformat() if self.expires_at else None,
            "max_devices": self.max_devices,
            "current_devices": self.current_devices or 0,
            "views_count": self.views_count or 0,
            "status": self.status,
            "dynamic_pin": self.dynamic_pin,
            "auto_terminate": self.auto_terminate,
            "require_biometric": self.require_biometric,
            "screenshot_protection": self.screenshot_protection,
            "watermarking": self.watermarking,
        }

class PIN(Base):
    __tablename__ = "pins"
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(String, ForeignKey("content.id"), nullable=False)
    pin_hash = Column(String, nullable=False)  # Hashed PIN
    pin_value = Column(String, nullable=False)  # Original PIN (encrypted at rest)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)
    rotation_schedule = Column(JSON, nullable=True)
    
    # Failed attempts tracking
    failed_attempts = Column(Integer, default=0)
    locked_until = Column(DateTime(timezone=True), nullable=True)
    
    # Relationships
    content = relationship("Content", back_populates="pins")
    
    def is_locked(self):
        if self.locked_until:
            return datetime.utcnow() < self.locked_until
        return False

class AccessSession(Base):
    __tablename__ = "access_sessions"
    
    id = Column(String, primary_key=True, index=True)
    content_id = Column(String, ForeignKey("content.id"), nullable=False)
    device_id = Column(String, nullable=False)
    device_fingerprint = Column(String, nullable=False)
    session_token = Column(String, nullable=False)
    
    # Session info
    started_at = Column(DateTime(timezone=True), server_default=func.now())
    last_activity = Column(DateTime(timezone=True), server_default=func.now())
    view_count = Column(Integer, default=0, nullable=False)  # FIXED: added nullable=False
    is_active = Column(Boolean, default=True)
    
    # Security
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    
    # Relationships
    content = relationship("Content", back_populates="access_sessions")
    
    def update_activity(self):
        self.last_activity = func.now()

class TrustedDevice(Base):
    __tablename__ = "trusted_devices"
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(String, ForeignKey("content.id"), nullable=False)
    device_fingerprint = Column(String, nullable=False)
    added_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    content = relationship("Content", back_populates="trusted_devices")

class SuspiciousActivity(Base):
    __tablename__ = "suspicious_activities"
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(String, ForeignKey("content.id"), nullable=False)
    activity_type = Column(String, nullable=False)  # failed_pin, screenshot, navigation, etc.
    device_id = Column(String, nullable=True)
    ip_address = Column(String, nullable=True)
    description = Column(Text, nullable=True)
    detected_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    content = relationship("Content", back_populates="suspicious_activities")

class DestructionCertificate(Base):
    __tablename__ = "destruction_certificates"
    
    id = Column(String, primary_key=True, index=True)
    content_id = Column(String, nullable=False, unique=True)
    reason = Column(String, nullable=False)  # expired, terminated, viewed, suspicious
    destroyed_at = Column(DateTime(timezone=True), server_default=func.now())
    proof_hash = Column(String, nullable=False)
    signature = Column(String, nullable=False)
    content_metadata = Column(JSON, nullable=True)  # FIXED: changed from 'metadata'