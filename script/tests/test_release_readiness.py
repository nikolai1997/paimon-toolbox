import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleaseReadinessTests(unittest.TestCase):
    def test_version_has_one_release_source(self):
        version_path = ROOT / "VERSION"
        self.assertTrue(version_path.is_file())
        version = version_path.read_text(encoding="utf-8").strip()
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")

        consumers = {
            "script/package_dmg.sh": '$ROOT_DIR/VERSION',
            "script/install_app.sh": '$ROOT_DIR/VERSION',
            "script/build_widget_extension_bundle.sh": '$ROOT_DIR/VERSION',
            "script/generate_xcode_project.py": 'ROOT / "VERSION"',
        }
        for relative_path, marker in consumers.items():
            with self.subTest(path=relative_path):
                source = (ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn(marker, source)
                self.assertNotIn('"0.1.1"', source)

        uigf_source = (ROOT / "Services/UIGFDocument.swift").read_text(encoding="utf-8")
        self.assertNotIn('exportAppVersion: "0.1.1"', uigf_source)

    def test_public_release_documents_third_party_notices(self):
        notice_path = ROOT / "THIRD_PARTY_NOTICES.md"
        self.assertTrue(notice_path.is_file())
        notice = notice_path.read_text(encoding="utf-8")
        for expected in (
            "theBowja/genshin-db",
            "Copyright (c) 2020 theBowja",
            "SnapHutaoRemasteringProject/Snap.Metadata",
            "Copyright (c) 2022 DGP Studio",
        ):
            self.assertIn(expected, notice)

        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("THIRD_PARTY_NOTICES.md", readme)

    def test_readme_uses_release_visuals_and_version_placeholder(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("docs/assets/app-icon.png", readme)
        self.assertIn("docs/assets/app-overview.png", readme)
        self.assertIn("PaimonToolbox-<version>.dmg", readme)
        self.assertNotIn("PaimonToolbox-0.1.1.dmg", readme)

    def test_readme_explains_unnotarized_first_launch(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("未经过 Apple 公证", readme)
        self.assertIn("右键", readme)
        self.assertIn("隐私与安全性", readme)

    def test_public_release_excludes_internal_agent_documents(self):
        internal_docs = ROOT / "docs" / "superpowers"
        self.assertFalse(internal_docs.exists(), list(internal_docs.rglob("*")))

    def test_data_source_document_matches_generator_outputs(self):
        document = (ROOT / "docs/data-source-configuration.md").read_text(encoding="utf-8")
        self.assertIn("python3 script/update_remote_data.py", document)
        self.assertNotIn("python3 tools/update_remote_data.py", document)
        self.assertIn("data-pack-YYYY.MM.DD.zip", document)
        self.assertNotIn("data-pack-latest.zip", document)

        metadata = json.loads((ROOT / "data/public/metadata.json").read_text(encoding="utf-8"))
        expected_counts = (
            f"角色 {len(metadata['characters'])}、"
            f"武器 {len(metadata['weapons'])}、"
            f"材料 {len(metadata['materials'])}"
        )
        self.assertIn(expected_counts, document)
        self.assertIsNone(re.search(r"角色 119、武器 236、材料 849", document))

    def test_bundled_metadata_matches_public_release(self):
        bundled = (ROOT / "Resources/metadata.sample.json").read_bytes()
        public = (ROOT / "data/public/metadata.json").read_bytes()
        self.assertEqual(bundled, public)

    def test_github_ci_runs_release_checks(self):
        workflow_path = ROOT / ".github/workflows/ci.yml"
        self.assertTrue(workflow_path.is_file())
        workflow = workflow_path.read_text(encoding="utf-8")
        for command in (
            "swift test --disable-sandbox",
            "python3 -m unittest discover -s script/tests -p 'test_*.py'",
            "python3 script/update_remote_data.py --self-test",
            "python3 script/update_remote_data.py --validate-public-dir data/public",
            "swift build -c release --disable-sandbox",
            ".build/release/PaimonToolbox --self-check",
            "https://nikolai1997.github.io/paimon-toolbox-data/announcements.json",
            "data.validate_announcement_feed",
        ):
            self.assertIn(command, workflow)

        self.assertNotIn("./script/package_dmg.sh", workflow)
        self.assertIn("CLANG_MODULE_CACHE_PATH: /tmp/paimon-toolbox-clang-cache", workflow)
        self.assertNotIn("CLANG_MODULE_CACHE_PATH: ${{ runner.temp }}", workflow)

        package_script = (ROOT / "script/package_dmg.sh").read_text(encoding="utf-8")
        self.assertIn('--validate-public-dir "$ROOT_DIR/data/public"', package_script)

    def test_swift_package_excludes_release_only_metadata(self):
        package = (ROOT / "Package.swift").read_text(encoding="utf-8")
        self.assertIn('"THIRD_PARTY_NOTICES.md"', package)
        self.assertIn('"VERSION"', package)

    def test_swift6_async_helpers_require_sendable_results(self):
        account_service = (ROOT / "Services/AccountSessionService.swift").read_text(encoding="utf-8")
        app_store = (ROOT / "Stores/AppStore.swift").read_text(encoding="utf-8")

        self.assertIn("runAccountSyncStep<T: Sendable>", account_service)
        self.assertIn("accountOperationWithTokenRefreshRetry<T: Sendable>", app_store)


if __name__ == "__main__":
    unittest.main()
