import json
import random
import string
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
from fastapi import UploadFile
import aiofiles
import os
from pathlib import Path
from config import settings

class FileUtils:
    @staticmethod
    async def save_uploaded_file(upload_file: UploadFile, content_id: str) -> str:
        """Save uploaded file to local storage (replace with cloud storage in production)"""
        # Create uploads directory if it doesn't exist
        upload_dir = Path("uploads")
        upload_dir.mkdir(exist_ok=True)
        
        # Generate filename
        file_ext = upload_file.filename.split('.')[-1] if '.' in upload_file.filename else 'dat'
        filename = f"{content_id}.{file_ext}"
        file_path = upload_dir / filename
        
        # Save file
        async with aiofiles.open(file_path, 'wb') as out_file:
            content = await upload_file.read()
            await out_file.write(content)
        
        # Return file URL/path
        return f"/uploads/{filename}"
    
    @staticmethod
    def get_file_url(file_path: str) -> str:
        """Get file URL for access"""
        # In production, this would return cloud storage URL
        return f"http://localhost:8000{file_path}"
    
    @staticmethod
    def delete_file(file_path: str):
        """Delete file from storage"""
        try:
            # Remove /uploads/ prefix if present
            if file_path.startswith("/uploads/"):
                file_path = file_path[1:]
            
            path = Path(file_path)
            if path.exists():
                path.unlink()
        except Exception as e:
            print(f"Error deleting file {file_path}: {e}")

class ContentUtils:
    @staticmethod
    def validate_content_type(content_type: str) -> bool:
        """Validate content type"""
        valid_types = ['text', 'image', 'pdf', 'video', 'audio', 'document']
        return content_type in valid_types
    
    @staticmethod
    def format_file_size(size_bytes: int) -> str:
        """Format file size for display"""
        if size_bytes < 1024:
            return f"{size_bytes} B"
        elif size_bytes < 1024 * 1024:
            return f"{size_bytes / 1024:.1f} KB"
        elif size_bytes < 1024 * 1024 * 1024:
            return f"{size_bytes / (1024 * 1024):.1f} MB"
        else:
            return f"{size_bytes / (1024 * 1024 * 1024):.1f} GB"
    
    @staticmethod
    def get_content_type_from_mime(mime_type: str) -> str:
        """Map MIME type to content type"""
        mime_to_type = {
            'text/plain': 'text',
            'image/jpeg': 'image',
            'image/png': 'image',
            'image/gif': 'image',
            'application/pdf': 'pdf',
            'video/mp4': 'video',
            'video/quicktime': 'video',
            'audio/mpeg': 'audio',
            'audio/wav': 'audio',
            'application/msword': 'document',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'document',
        }
        return mime_to_type.get(mime_type, 'document')

class TimeUtils:
    @staticmethod
    def format_time_remaining(expiry_time: Optional[datetime]) -> str:
        """Format time remaining for display"""
        if not expiry_time:
            return "No expiry"
        
        now = datetime.utcnow()
        if now > expiry_time:
            return "Expired"
        
        delta = expiry_time - now
        total_seconds = int(delta.total_seconds())
        
        if total_seconds < 60:
            return f"{total_seconds}s"
        elif total_seconds < 3600:
            minutes = total_seconds // 60
            seconds = total_seconds % 60
            return f"{minutes}m {seconds}s"
        elif total_seconds < 86400:
            hours = total_seconds // 3600
            minutes = (total_seconds % 3600) // 60
            return f"{hours}h {minutes}m"
        else:
            days = total_seconds // 86400
            hours = (total_seconds % 86400) // 3600
            return f"{days}d {hours}h"