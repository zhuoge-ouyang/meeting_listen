import unittest

from services.meeting_analysis import normalize_action_items, render_meeting_minutes


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


if __name__ == "__main__":
    unittest.main()
