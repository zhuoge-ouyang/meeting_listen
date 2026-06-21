import unittest

from services.meeting_analysis import (
    normalize_action_items,
    render_meeting_minutes,
    resolve_translation_source_text,
)


class MeetingAnalysisTests(unittest.TestCase):
    def test_action_item_is_important_only_at_three_speakers(self):
        items = normalize_action_items(
            [
                {
                    "text": "补齐仓库防雨防风物料",
                    "speaker_ids": ["speaker_1", "speaker_2"],
                },
                {
                    "text": "完成 ITSM 关闭",
                    "speaker_ids": ["speaker_1", "speaker_2", "speaker_3"],
                },
            ]
        )

        self.assertFalse(items[0].is_important)
        self.assertTrue(items[1].is_important)

    def test_minutes_renderer_marks_important_items(self):
        item = normalize_action_items(
            [
                {
                    "text": "补齐仓库防雨防风物料",
                    "owner": "仓库",
                    "due": "尽快",
                    "speaker_ids": ["speaker_1", "speaker_2", "speaker_3"],
                }
            ]
        )[0]
        rendered = render_meeting_minutes(
            meeting_time="6月10日 07:50-08:10",
            participants=["仓储物流全体成员"],
            minutes=["各组长工作汇报"],
            action_items=[item],
        )

        self.assertIn("【重要】补齐仓库防雨防风物料", rendered)
        self.assertIn("负责人：仓库", rendered)

    def test_translation_text_does_not_require_meeting_store(self):
        source_text = resolve_translation_source_text(
            text="测试翻译",
            segment_ids=[],
            meeting=None,
        )

        self.assertEqual(source_text, "测试翻译")

    def test_translation_can_read_selected_segments_from_meeting(self):
        source_text = resolve_translation_source_text(
            text=None,
            segment_ids=[0, 2],
            meeting={
                "transcript_segments": [
                    {"text": "第一句"},
                    {"text": "第二句"},
                    {"text": "第三句"},
                ]
            },
        )

        self.assertEqual(source_text, "第一句\n第三句")


if __name__ == "__main__":
    unittest.main()
