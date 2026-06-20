"""Aliyun OSS upload helper for DashScope file-transcription URLs."""

from __future__ import annotations

from datetime import datetime
import os
import uuid

import oss2


class AliyunOSSService:
    def __init__(
        self,
        *,
        access_key_id: str | None,
        access_key_secret: str | None,
        endpoint: str | None,
        bucket_name: str | None,
        public_base_url: str | None = None,
        expire_seconds: int = 3600,
    ) -> None:
        self.access_key_id = access_key_id
        self.access_key_secret = access_key_secret
        self.endpoint = endpoint
        self.bucket_name = bucket_name
        self.public_base_url = public_base_url.rstrip("/") if public_base_url else None
        self.expire_seconds = expire_seconds

    @property
    def configured(self) -> bool:
        return bool(
            self.access_key_id
            and self.access_key_secret
            and self.endpoint
            and self.bucket_name
        )

    def upload_file(self, local_path: str, *, suffix: str = ".mp3") -> str:
        if not self.configured:
            raise RuntimeError(
                "Aliyun OSS is not configured. Set ALIYUN_ACCESS_KEY_ID, "
                "ALIYUN_ACCESS_KEY_SECRET, ALIYUN_OSS_ENDPOINT and "
                "ALIYUN_OSS_BUCKET."
            )
        auth = oss2.Auth(self.access_key_id, self.access_key_secret)
        bucket = oss2.Bucket(auth, self.endpoint, self.bucket_name)
        key = self._object_key(suffix)
        bucket.put_object_from_file(key, local_path)
        if self.public_base_url:
            return f"{self.public_base_url}/{key}"
        return bucket.sign_url("GET", key, self.expire_seconds)

    @staticmethod
    def _object_key(suffix: str) -> str:
        suffix = suffix if suffix.startswith(".") else f".{suffix}"
        day = datetime.utcnow().strftime("%Y/%m/%d")
        return f"recordwise/{day}/{uuid.uuid4().hex}{suffix}"
