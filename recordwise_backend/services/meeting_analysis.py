"""Meeting analysis helpers shared by API services and tests."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
import json
import re


IMPORTANT_SPEAKER_THRESHOLD = 3


@dataclass(slots=True)
class TranscriptSegment:
    speaker_id: str
    start_ms: int
    end_ms: int
    text: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "speaker_id": self.speaker_id,
            "start_ms": self.start_ms,
            "end_ms": self.end_ms,
            "text": self.text,
        }


@dataclass(slots=True)
class ActionItem:
    text: str
    owner: str | None = None
    due: str | None = None
    speaker_ids: set[str] = field(default_factory=set)
    evidence: list[str] = field(default_factory=list)

    @property
    def is_important(self) -> bool:
        return len(self.speaker_ids) >= IMPORTANT_SPEAKER_THRESHOLD

    def as_dict(self) -> dict[str, Any]:
        return {
            "text": self.text,
            "owner": self.owner,
            "due": self.due,
            "speaker_ids": sorted(self.speaker_ids),
            "speaker_count": len(self.speaker_ids),
            "is_important": self.is_important,
            "evidence": self.evidence,
        }


def transcript_text_from_segments(segments: list[TranscriptSegment]) -> str:
    lines: list[str] = []
    for seg in segments:
        start = _format_mmss(seg.start_ms)
        end = _format_mmss(seg.end_ms)
        lines.append(f"[{seg.speaker_id} {start}-{end}] {seg.text}")
    return "\n".join(lines)


def parse_speaker_lines(transcript: str) -> list[TranscriptSegment]:
    """Best-effort parser for legacy `Speaker N: text` transcripts."""
    segments: list[TranscriptSegment] = []
    if not transcript.strip():
        return segments
    line_pattern = re.compile(r"^\s*(?:Speaker|发言人|說話人)\s*([A-Za-z0-9_-]+)\s*[:：]\s*(.+)$")
    for index, raw in enumerate(transcript.splitlines()):
        text = raw.strip()
        if not text:
            continue
        match = line_pattern.match(text)
        if match:
            speaker_id = f"speaker_{match.group(1)}"
            content = match.group(2).strip()
        else:
            speaker_id = "speaker_1"
            content = text
        segments.append(
            TranscriptSegment(
                speaker_id=speaker_id,
                start_ms=index * 30_000,
                end_ms=(index + 1) * 30_000,
                text=content,
            )
        )
    return segments


def parse_summary_payload(raw_text: str) -> dict[str, Any]:
    """Parse a Qwen JSON response, tolerating fenced Markdown wrappers."""
    text = raw_text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return {
            "meeting_time": "",
            "participants": [],
            "minutes": [raw_text.strip()] if raw_text.strip() else [],
            "action_items": [],
            "summary_text": raw_text.strip(),
        }
    return payload if isinstance(payload, dict) else {}


def normalize_action_items(raw_items: list[Any]) -> list[ActionItem]:
    items: list[ActionItem] = []
    for raw in raw_items:
        if isinstance(raw, str):
            item = ActionItem(text=raw.strip())
        elif isinstance(raw, dict):
            speaker_values = raw.get("speaker_ids") or raw.get("speakers") or []
            if isinstance(speaker_values, str):
                speaker_values = [speaker_values]
            item = ActionItem(
                text=str(raw.get("text") or raw.get("task") or "").strip(),
                owner=raw.get("owner"),
                due=raw.get("due"),
                speaker_ids={str(v) for v in speaker_values if str(v).strip()},
                evidence=[
                    str(v)
                    for v in (raw.get("evidence") or [])
                    if str(v).strip()
                ],
            )
        else:
            continue
        if item.text:
            items.append(item)
    return items


def render_meeting_minutes(
    *,
    meeting_time: str,
    participants: list[str],
    minutes: list[str],
    action_items: list[ActionItem],
) -> str:
    lines = [
        "会议时间:",
        meeting_time or "未识别",
        "参会人员:",
        "、".join(participants) if participants else "未识别",
        "会议纪要:",
    ]
    for index, item in enumerate(minutes, 1):
        lines.append(f"{index}. {item}")
    if action_items:
        lines.append("待办事项:")
        for index, item in enumerate(action_items, 1):
            marker = "【重要】" if item.is_important else ""
            owner = f"（负责人：{item.owner}）" if item.owner else ""
            due = f"（截止：{item.due}）" if item.due else ""
            lines.append(f"{index}. {marker}{item.text}{owner}{due}")
    return "\n".join(lines)


def build_summary_prompt(
    *,
    meeting_title: str | None,
    participant_names: str | None,
    segments: list[TranscriptSegment],
    template_text: str | None = None,
    module: str = "default",
) -> str:
    transcript = transcript_text_from_segments(segments)
    template = (template_text or "").strip()
    template_instruction = ""
    if module == "imported" and template:
        template_instruction = f"""

用户导入的会议纪要模板如下。请先理解它的标题层级、字段顺序、编号方式、语气和待办写法，然后按这个模板风格生成完整纪要。
不要照抄模板里的示例内容；必须用本次会议转写替换内容。无法从转写判断的信息写“未识别”。

导入模板：
{template}
"""
    return f"""请根据以下带说话人和时间戳的会议转写，生成严格 JSON，不要输出 Markdown。

要求：
1. `meeting_time` 尽量从元信息或转写里提取，无法识别则留空。
2. `participants` 输出参会人员姓名；若只有 speaker_id，则输出 speaker_id。
3. `minutes` 输出会议纪要条目，风格贴近工厂/业务会议纪要，编号由客户端渲染。
4. `action_items` 输出待办数组，每项包含 text、owner、due、speaker_ids、evidence。
5. 同一事项如果被多个说话人提到，必须合并为同一 action item，并在 speaker_ids 中列出不同 speaker_id。

JSON 结构：
{{
  "meeting_time": "",
  "participants": [],
  "minutes": [],
  "summary_text": "",
  "action_items": [
    {{"text": "", "owner": "", "due": "", "speaker_ids": [], "evidence": []}}
  ]
}}

会议标题：{meeting_title or "未命名会议"}
用户提供参会人员：{participant_names or "未提供"}
总结模块：{module}
{template_instruction}
会议转写：
{transcript}
"""


def resolve_translation_source_text(
    *,
    text: str | None,
    segment_ids: list[int],
    meeting: dict[str, Any] | None,
) -> str:
    source_text = (text or "").strip()
    if source_text or not segment_ids or meeting is None:
        return source_text
    segments = meeting.get("transcript_segments") or []
    return "\n".join(
        str(segments[i]["text"])
        for i in segment_ids
        if 0 <= i < len(segments) and isinstance(segments[i], dict)
    ).strip()


def _format_mmss(ms: int) -> str:
    total = max(ms, 0) // 1000
    minutes = total // 60
    seconds = total % 60
    return f"{minutes:02d}:{seconds:02d}"
