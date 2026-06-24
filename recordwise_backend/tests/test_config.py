import unittest
from pathlib import Path

from utils.config import Settings, get_config_status, get_env_file_path


class ConfigTests(unittest.TestCase):
    def test_env_file_path_points_to_backend_directory(self):
        expected = Path(__file__).resolve().parents[1] / ".env"

        self.assertEqual(get_env_file_path(), expected)
        self.assertEqual(Path(Settings.model_config["env_file"]), expected)

    def test_config_status_reports_missing_required_keys_without_values(self):
        settings = Settings(
            DASHSCOPE_API_KEY=None,
            ALIYUN_ACCESS_KEY_ID="",
            ALIYUN_ACCESS_KEY_SECRET=None,
            ALIYUN_OSS_ENDPOINT="https://oss-cn-beijing.aliyuncs.com",
            ALIYUN_OSS_BUCKET="meeting-listen",
        )

        status = get_config_status(settings)

        self.assertIsInstance(status["env_file_exists"], bool)
        self.assertEqual(
            status["missing_required"],
            [
                "DASHSCOPE_API_KEY",
                "ALIYUN_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_SECRET",
            ],
        )
        self.assertNotIn("values", status)

    def test_placeholder_values_are_treated_as_missing(self):
        settings = Settings(
            DASHSCOPE_API_KEY="<your-dashscope-api-key>",
            ALIYUN_ACCESS_KEY_ID="<your-aliyun-access-key-id>",
            ALIYUN_ACCESS_KEY_SECRET="<your-aliyun-access-key-secret>",
            ALIYUN_OSS_ENDPOINT="https://oss-cn-beijing.aliyuncs.com",
            ALIYUN_OSS_BUCKET="<your-oss-bucket>",
        )

        status = get_config_status(settings)

        self.assertEqual(
            status["missing_required"],
            [
                "DASHSCOPE_API_KEY",
                "ALIYUN_ACCESS_KEY_ID",
                "ALIYUN_ACCESS_KEY_SECRET",
                "ALIYUN_OSS_BUCKET",
            ],
        )


if __name__ == "__main__":
    unittest.main()
