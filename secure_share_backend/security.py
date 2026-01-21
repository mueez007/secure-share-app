import hashlib
import secrets
import string
from datetime import datetime, timedelta
from typing import Optional
import json  # ADD THIS
from cryptography.fernet import Fernet
import base64
from config import settings  # ADD THIS

class SecurityUtils:
    @staticmethod
    def generate_pin(length: int = 4) -> str:
        """Generate a random numeric PIN"""
        return ''.join(secrets.choice(string.digits) for _ in range(length))
    
    @staticmethod
    def hash_pin(pin: str) -> str:
        """Hash PIN for storage"""
        salt = secrets.token_bytes(16)
        pin_bytes = pin.encode()
        hash_obj = hashlib.pbkdf2_hmac('sha256', pin_bytes, salt, 100000)
        return f"{salt.hex()}:{hash_obj.hex()}"
    
    @staticmethod
    def verify_pin(pin: str, hashed_pin: str) -> bool:
        """Verify PIN against hash"""
        try:
            salt_hex, hash_hex = hashed_pin.split(':')
            salt = bytes.fromhex(salt_hex)
            pin_bytes = pin.encode()
            hash_obj = hashlib.pbkdf2_hmac('sha256', pin_bytes, salt, 100000)
            return hash_obj.hex() == hash_hex
        except:
            return False
    
    @staticmethod
    def generate_session_token() -> str:
        """Generate secure session token"""
        return secrets.token_urlsafe(32)
    
    @staticmethod
    def generate_device_fingerprint(device_info: dict) -> str:
        """Generate device fingerprint from device info"""
        device_str = json.dumps(device_info, sort_keys=True)
        return hashlib.sha256(device_str.encode()).hexdigest()
    
    @staticmethod
    def encrypt_key_for_storage(key: str) -> str:
        """Encrypt content key for storage"""
        # Use settings.SECRET_KEY from config
        fernet_key = base64.urlsafe_b64encode(
            hashlib.sha256(settings.SECRET_KEY.encode()).digest()[:32]
        )
        cipher = Fernet(fernet_key)
        return cipher.encrypt(key.encode()).decode()
    
    @staticmethod
    def decrypt_key_from_storage(encrypted_key: str) -> str:
        """Decrypt content key from storage"""
        fernet_key = base64.urlsafe_b64encode(
            hashlib.sha256(settings.SECRET_KEY.encode()).digest()[:32]
        )
        cipher = Fernet(fernet_key)
        return cipher.decrypt(encrypted_key.encode()).decode()
    
    @staticmethod
    def is_expired(expiry_time: Optional[datetime]) -> bool:
        """Check if content is expired"""
        if not expiry_time:
            return False
        return datetime.utcnow() > expiry_time
    
    @staticmethod
    def calculate_expiry_time(duration_minutes: Optional[int]) -> Optional[datetime]:
        """Calculate expiry time from duration"""
        if not duration_minutes:
            return None
        return datetime.utcnow() + timedelta(minutes=duration_minutes)
    
    @staticmethod
    def generate_proof_of_destruction(content_id: str, reason: str) -> dict:
        """Generate proof of destruction certificate"""
        timestamp = datetime.utcnow().isoformat()
        data = f"{content_id}:{reason}:{timestamp}"
        proof_hash = hashlib.sha256(data.encode()).hexdigest()
        
        # Sign with server secret (for verification)
        signature_data = f"{proof_hash}:{settings.SECRET_KEY}"
        signature = hashlib.sha256(signature_data.encode()).hexdigest()
        
        return {
            "content_id": content_id,
            "reason": reason,
            "timestamp": timestamp,
            "proof_hash": proof_hash,
            "signature": signature,
            "signed_by": "SecureShareSystem"
        }