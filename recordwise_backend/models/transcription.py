"""
RecordWise Data Models
"""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any

class LanguageInfo(BaseModel):
    """Language detection information"""
    code: str = Field(description="Language code (e.g., 'zh-TW', 'zh-CN', 'en')")
    name: str = Field(description="Language name (e.g., 'Cantonese (Traditional Chinese)')")
    native: str = Field(description="Native language name (e.g., '粵語 (繁體中文)')")
    script: str = Field(description="Script type (e.g., 'traditional', 'simplified', 'latin')")
    confidence: Optional[float] = Field(default=None, description="Detection confidence score")

class TranscriptionResponse(BaseModel):
    """Response model for transcription results"""
    success: bool
    session_id: str = Field(description="Unique session identifier")
    transcription_id: str = Field(description="Unique transcription identifier")
    transcription: str = Field(description="Full transcript text")
    summary: str = Field(description="AI-generated summary")
    action_items: List[Any] = Field(description="Extracted action items")
    key_points: List[str] = Field(description="Key discussion points")
    full_analysis: str = Field(description="Complete AI analysis")
    transcript_segments: List[Dict[str, Any]] = Field(default_factory=list)
    structured_action_items: List[Dict[str, Any]] = Field(default_factory=list)
    participants: List[str] = Field(default_factory=list)
    meeting_time: Optional[str] = None
    meeting_type: str
    meeting_title: str
    language: str = Field(description="Original language parameter (for backwards compatibility)")
    detected_language: LanguageInfo = Field(description="Automatically detected language information")
    duration_minutes: float
    word_count: int
    participant_count: Optional[int] = None
    created_at: str
    file_size_mb: float


class SpeakerAliasRequest(BaseModel):
    speaker_aliases: Dict[str, str] = Field(default_factory=dict)


class TranslateTTSRequest(BaseModel):
    text: Optional[str] = None
    segment_ids: List[int] = Field(default_factory=list)
    target_language: str


class TranslateTTSResponse(BaseModel):
    translated_text: str
    audio_url: str
    voice: str
    language: str
    status: str
