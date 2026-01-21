import json
import os
from pathlib import Path
from typing import Optional
from datetime import datetime
import aiofiles
from fastapi import UploadFile

class FileUtils:
    @staticmethod
    async def save_uploaded_file(upload_file: UploadFile, content_id: str) -> str:
        """Save uploaded file to local storage"""
        # Create uploads directory if it doesn't exist
        upload_dir = Path("uploads")
        upload_dir.mkdir(exist_ok=True)
        
        # Generate filename
        if upload_file.filename and '.' in upload_file.filename:
            file_ext = upload_file.filename.split('.')[-1]
        else:
            file_ext = 'dat'
        
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
        """Get file URL for access - FIXED for macOS"""
        # Use 127.0.0.1 instead of localhost for better compatibility
        return f"http://127.0.0.1:8000{file_path}"
    
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
                print(f"🗑️ Deleted file: {file_path}")
        except Exception as e:
            print(f"⚠️ Error deleting file {file_path}: {e}")

class ContentUtils:
    @staticmethod
    def validate_content_type(content_type: str) -> bool:
        """Validate content type"""
        valid_types = ['text', 'image', 'pdf', 'video', 'audio', 'document']
        return content_type in valid_types
    
    @staticmethod
    def format_file_size(size_bytes: int) -> str:
        """Format file size for display"""
        if size_bytes is None:
            return "0 B"
        
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
            'application/octet-stream': 'document',
        }
        return mime_to_type.get(mime_type, 'document')
    
    @staticmethod
    def get_mime_type(filename: str) -> str:
        """Get MIME type from filename"""
        ext = filename.split('.')[-1].lower() if '.' in filename else ''
        mime_map = {
            'txt': 'text/plain',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'pdf': 'application/pdf',
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'mp3': 'audio/mpeg',
            'wav': 'audio/wav',
            'doc': 'application/msword',
            'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        }
        return mime_map.get(ext, 'application/octet-stream')

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
    
    @staticmethod
    def seconds_until(expiry_time: Optional[datetime]) -> int:
        """Get seconds until expiry"""
        if not expiry_time:
            return 0
        
        now = datetime.utcnow()
        if now > expiry_time:
            return 0
        
        delta = expiry_time - now
        return int(delta.total_seconds())