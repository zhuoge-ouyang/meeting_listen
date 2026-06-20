"""
RecordWise Audio Processing Service

Normalises any incoming audio (WAV, MP3, M4A, WebM/Opus, MP4, FLAC, etc.)
to a compact, transcription-friendly MP3:

    * 16 kHz mono
    * 32 kbps libmp3lame

For 60 minutes of speech this yields roughly 14 MB, well under the 500 MB
/ 2-hour limit of the Azure AI Speech Fast Transcription endpoint used by
:class:`AzureSpeechSTTService`.  Speaker diarization is also more accurate
at 16 kHz mono than on raw stereo recordings.

The bundled ffmpeg binary from the ``imageio-ffmpeg`` package is used so the
backend works in any environment (container, serverless, fresh laptop) without
requiring a system ``brew install ffmpeg`` step.
"""

import asyncio
import logging
import os
import re
import subprocess
import tempfile

import imageio_ffmpeg

logger = logging.getLogger("RecordWise.AudioProcessor")


_FFMPEG_BIN = imageio_ffmpeg.get_ffmpeg_exe()
_DURATION_RE = re.compile(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)")


class AudioProcessingError(RuntimeError):
    """Raised when ffmpeg fails to decode or transcode the input audio."""


class AudioProcessor:
    """Convert arbitrary audio uploads to a normalized 16 kHz mono MP3."""

    def __init__(
        self,
        target_sample_rate: int = 16000,
        target_channels: int = 1,
        target_bitrate: str = "32k",
    ):
        self.target_sample_rate = target_sample_rate
        self.target_channels = target_channels
        self.target_bitrate = target_bitrate

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def process_for_transcription(self, input_path: str) -> str:
        """Transcode *input_path* to a normalized MP3 and return the new path.

        Raises:
            AudioProcessingError: if the file is missing, empty, or ffmpeg
                cannot decode it.
        """
        if not os.path.exists(input_path):
            raise AudioProcessingError(f"Input file does not exist: {input_path}")

        in_size = os.path.getsize(input_path)
        if in_size <= 0:
            raise AudioProcessingError("Input file is empty")

        logger.info("Processing audio: %s (%d bytes)", input_path, in_size)

        out_fd, out_path = tempfile.mkstemp(suffix="_processed.mp3")
        os.close(out_fd)

        cmd = [
            _FFMPEG_BIN,
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", input_path,
            "-vn",
            "-ac", str(self.target_channels),
            "-ar", str(self.target_sample_rate),
            "-c:a", "libmp3lame",
            "-b:a", self.target_bitrate,
            out_path,
        ]

        try:
            await asyncio.get_event_loop().run_in_executor(
                None, lambda: self._run_ffmpeg(cmd)
            )
        except AudioProcessingError:
            if os.path.exists(out_path):
                os.unlink(out_path)
            raise

        out_size = os.path.getsize(out_path) if os.path.exists(out_path) else 0
        if out_size <= 0:
            raise AudioProcessingError("ffmpeg produced an empty output file")

        logger.info(
            "Audio normalized: %s (%d bytes -> %d bytes, %.1fx compression)",
            out_path,
            in_size,
            out_size,
            in_size / out_size if out_size else 0.0,
        )
        return out_path

    async def get_audio_duration(self, file_path: str) -> float:
        """Return the duration of *file_path* in seconds.

        Uses ffmpeg's stderr output (``Duration: HH:MM:SS.ms``) so it works on
        any container format ffmpeg can decode.  Returns 0.0 when the duration
        cannot be determined.
        """
        if not os.path.exists(file_path):
            logger.warning("File does not exist for duration calculation: %s", file_path)
            return 0.0

        cmd = [_FFMPEG_BIN, "-hide_banner", "-i", file_path]
        try:
            proc = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: subprocess.run(cmd, capture_output=True, text=True, check=False),
            )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("ffmpeg duration probe failed: %s", exc)
            return 0.0

        # ffmpeg writes container metadata to stderr even with no output file
        match = _DURATION_RE.search(proc.stderr or "")
        if not match:
            logger.warning("Could not parse duration from ffmpeg output")
            return 0.0
        hours, minutes, seconds = match.groups()
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _run_ffmpeg(cmd: list[str]) -> None:
        """Run ffmpeg synchronously, surfacing decoder errors as exceptions."""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        except FileNotFoundError as exc:
            raise AudioProcessingError(f"ffmpeg binary not found: {exc}") from exc

        if result.returncode != 0:
            stderr_tail = (result.stderr or "").strip().splitlines()[-5:]
            raise AudioProcessingError(
                "ffmpeg failed (exit {}): {}".format(
                    result.returncode, " | ".join(stderr_tail)
                )
            )

    @staticmethod
    def get_ffmpeg_path() -> str:
        """Expose the resolved ffmpeg binary path (useful for other services)."""
        return _FFMPEG_BIN
