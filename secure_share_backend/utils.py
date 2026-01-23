import json
import os
from pathlib import Path
from typing import Optional, Dict
from datetime import datetime
import aiofiles
from fastapi import UploadFile

class FileUtils:
    @staticmethod
    async def save_uploaded_file(upload_file: UploadFile, content_id: str) -> str:
        """Save uploaded file to local storage with proper extension handling"""
        # Create uploads directory if it doesn't exist
        upload_dir = Path("uploads")
        upload_dir.mkdir(exist_ok=True)
        
        # Map content types to extensions
        content_type_to_ext = {
            'image/jpeg': 'jpg',
            'image/jpg': 'jpg',
            'image/png': 'png',
            'image/gif': 'gif',
            'image/webp': 'webp',
            'application/pdf': 'pdf',
            'video/mp4': 'mp4',
            'video/quicktime': 'mov',
            'video/webm': 'webm',
            'audio/mpeg': 'mp3',
            'audio/mp3': 'mp3',
            'audio/wav': 'wav',
            'audio/ogg': 'ogg',
            'text/plain': 'txt',
            'text/csv': 'csv',
            'text/html': 'html',
            'application/json': 'json',
            'application/zip': 'zip',
            'application/x-zip-compressed': 'zip',
            'application/msword': 'doc',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
        }
        
        # Get original filename and content type
        original_filename = upload_file.filename or "file"
        content_type = (upload_file.content_type or "").lower()
        
        # Determine file extension
        file_ext = ""
        
        # First, try to get extension from original filename
        if '.' in original_filename:
            file_ext = original_filename.split('.')[-1].lower()
        
        # If no extension from filename, try to get from content type
        if not file_ext and content_type:
            file_ext = content_type_to_ext.get(content_type, 'dat')
        
        # If still no extension, use a default based on content type pattern
        if not file_ext:
            if 'image' in content_type:
                file_ext = 'jpg'
            elif 'pdf' in content_type:
                file_ext = 'pdf'
            elif 'video' in content_type:
                file_ext = 'mp4'
            elif 'audio' in content_type:
                file_ext = 'mp3'
            elif 'text' in content_type:
                file_ext = 'txt'
            else:
                file_ext = 'dat'
        
        # Ensure extension is safe (alphanumeric only)
        file_ext = ''.join(c for c in file_ext if c.isalnum()).lower()
        if not file_ext:
            file_ext = 'dat'
        
        # Generate filename
        filename = f"{content_id}.{file_ext}"
        file_path = upload_dir / filename
        
        # Save file
        async with aiofiles.open(file_path, 'wb') as out_file:
            content = await upload_file.read()
            await out_file.write(content)
        
        print(f"💾 File saved: {filename} (type: {content_type}, ext: .{file_ext})")
        
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
    
    @staticmethod
    def get_file_extension(file_path: str) -> str:
        """Get file extension from path"""
        path = Path(file_path)
        if '.' in path.name:
            return path.name.split('.')[-1].lower()
        return ""
    
    @staticmethod
    def guess_content_type_from_extension(file_path: str) -> str:
        """Guess content type from file extension"""
        ext = FileUtils.get_file_extension(file_path)
        
        ext_to_mime = {
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'png': 'image/png',
            'gif': 'image/gif',
            'webp': 'image/webp',
            'pdf': 'application/pdf',
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'webm': 'video/webm',
            'mp3': 'audio/mpeg',
            'wav': 'audio/wav',
            'ogg': 'audio/ogg',
            'txt': 'text/plain',
            'csv': 'text/csv',
            'html': 'text/html',
            'json': 'application/json',
            'zip': 'application/zip',
            'doc': 'application/msword',
            'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        }
        
        return ext_to_mime.get(ext, 'application/octet-stream')

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
            'image/webp': 'image',
            'application/pdf': 'pdf',
            'video/mp4': 'video',
            'video/quicktime': 'video',
            'video/webm': 'video',
            'audio/mpeg': 'audio',
            'audio/wav': 'audio',
            'audio/ogg': 'audio',
            'application/msword': 'document',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'document',
            'application/vnd.ms-excel': 'document',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'document',
            'application/vnd.ms-powerpoint': 'document',
            'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'document',
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
            'webp': 'image/webp',
            'pdf': 'application/pdf',
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'webm': 'video/webm',
            'mp3': 'audio/mpeg',
            'wav': 'audio/wav',
            'ogg': 'audio/ogg',
            'doc': 'application/msword',
            'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls': 'application/vnd.ms-excel',
            'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt': 'application/vnd.ms-powerpoint',
            'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        }
        return mime_map.get(ext, 'application/octet-stream')
    
    @staticmethod
    def get_simplified_content_type(mime_type: str) -> str:
        """Get simplified content type (image, video, audio, pdf, document, text)"""
        mime = mime_type.lower()
        if mime.startswith('image/'):
            return 'image'
        elif mime.startswith('video/'):
            return 'video'
        elif mime.startswith('audio/'):
            return 'audio'
        elif mime == 'application/pdf':
            return 'pdf'
        elif mime.startswith('text/'):
            return 'text'
        else:
            return 'document'

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
            minutes = (total_seconds % 3600) // 60
            return f"{days}d {hours}h {minutes}m"
    
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
    
    @staticmethod
    def format_duration_hhmmss(total_seconds: int) -> str:
        """Format seconds as HH:MM:SS"""
        if total_seconds < 0:
            total_seconds = 0
        
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        seconds = total_seconds % 60
        
        if hours > 0:
            return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        else:
            return f"{minutes:02d}:{seconds:02d}"