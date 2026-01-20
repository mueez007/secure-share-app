import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    PROJECT_NAME = "SecureShare Backend"
    PROJECT_VERSION = "1.0.0"
    
    # Security
    SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-change-in-production")
    ALGORITHM = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES = 30
    
    # Database
    DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./secure_share.db")
    
    # Redis for caching and rate limiting
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
    
    # File upload settings
    MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB
    ALLOWED_CONTENT_TYPES = {
        'image/jpeg', 'image/png', 'image/gif',
        'application/pdf',
        'video/mp4', 'video/quicktime',
        'audio/mpeg', 'audio/wav',
        'text/plain',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    }
    
    # Security settings
    MAX_PIN_ATTEMPTS = 3
    PIN_LOCKOUT_MINUTES = 15
    PIN_ROTATION_INTERVALS = [10, 30, 60, 120, 360, 720]  # minutes
    
    # Cloud storage (configure based on your provider)
    CLOUD_PROVIDER = os.getenv("CLOUD_PROVIDER", "local")  # local, s3, gcs
    CLOUD_BUCKET = os.getenv("CLOUD_BUCKET", "secure-share-content")
    
    # Content cleanup
    CLEANUP_INTERVAL_MINUTES = 5

settings = Settings()