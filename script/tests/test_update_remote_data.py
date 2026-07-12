import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "update_remote_data.py"
SPEC = importlib.util.spec_from_file_location("update_remote_data", MODULE_PATH)
assert SPEC and SPEC.loader
update_remote_data = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = update_remote_data
SPEC.loader.exec_module(update_remote_data)


class UpdateRemoteDataTests(unittest.TestCase):
    @staticmethod
    def make_payload() -> update_remote_data.RemoteDataPayload:
        return update_remote_data.RemoteDataPayload(
            source="test-source",
            version_prefix="test",
            characters=[{"id": 1, "name": "测试角色"}],
            weapons=[{"id": 2, "name": "测试武器"}],
            materials=[{"id": 3, "name": "测试材料"}],
            gacha_events=[{"name": "测试卡池", "type": 301}],
            announcements={"schemaVersion": 1, "updatedAt": "2026-07-10T00:00:00Z", "items": []},
        )

    def test_main_resolves_relative_paths_from_script_repository_root(self):
        repository_root = MODULE_PATH.parents[1]
        generated = [update_remote_data.GeneratedFile("manifest.json", "manifest")]
        payload = self.make_payload()

        with tempfile.TemporaryDirectory() as temporary:
            previous = Path.cwd()
            try:
                os.chdir(temporary)
                with (
                    mock.patch.object(
                        sys,
                        "argv",
                        [
                            str(MODULE_PATH),
                            "--source",
                            "genshin-db",
                            "--gacha-source",
                            "manual",
                            "--genshin-db-cache",
                            "relative-cache",
                            "--manual-dir",
                            "relative-manual",
                            "--official-announcements-json",
                            "relative-announcements.json",
                            "--public-dir",
                            "relative-public",
                            "--release-dir",
                            "relative-release",
                        ],
                    ),
                    mock.patch.object(update_remote_data, "load_announcements", return_value=payload.announcements) as load_announcements,
                    mock.patch.object(update_remote_data, "read_json", return_value=payload.gacha_events),
                    mock.patch.object(update_remote_data, "ensure_genshin_db_checkout") as ensure_checkout,
                    mock.patch.object(update_remote_data, "build_genshin_db_payload", return_value=payload),
                    mock.patch.object(update_remote_data, "generate_public_data", return_value=generated) as generate,
                    mock.patch.object(
                        update_remote_data,
                        "package_release",
                        return_value=repository_root / "relative-release" / "data-pack.zip",
                    ) as package,
                ):
                    self.assertEqual(update_remote_data.main(), 0)
            finally:
                os.chdir(previous)

        ensure_checkout.assert_called_once_with(repository_root / "relative-cache", skip_fetch=False)
        load_announcements.assert_called_once_with(
            repository_root / "relative-manual",
            official_announcements_json=repository_root / "relative-announcements.json",
            fetch_official_announcements=False,
            current_public_announcements=repository_root / "relative-public" / "announcements.json",
        )
        generate.assert_called_once_with(payload, repository_root / "relative-public", "")
        package.assert_called_once_with(repository_root / "relative-public", repository_root / "relative-release", generated)

    def test_official_announcement_fields_match_swift_decoder(self):
        converted = update_remote_data.convert_official_announcements(
            {
                "data": {
                    "list": [
                        {
                            "type_label": "活动公告",
                            "list": [
                                {
                                    "ann_id": 7,
                                    "title": "测试公告",
                                    "subtitle": "副标题",
                                    "start_time": "2026-07-10 10:00:00",
                                    "end_time": "2026-07-11 10:00:00",
                                    "content_url": "https://www.mihoyo.com/notice/7",
                                }
                            ],
                        }
                    ]
                }
            }
        )

        item = converted["items"][0]
        self.assertEqual(item["startTime"], "2026-07-10 10:00:00")
        self.assertEqual(item["endTime"], "2026-07-11 10:00:00")
        self.assertEqual(item["type"], "活动公告")
        self.assertEqual(item["contentURL"], "https://www.mihoyo.com/notice/7")
        self.assertNotIn("startsAt", item)
        self.assertNotIn("url", item)

    def test_official_announcement_empty_urls_become_null(self):
        converted = update_remote_data.convert_official_announcements(
            {
                "data": {
                    "list": [
                        {
                            "type_label": "游戏公告",
                            "list": [
                                {
                                    "ann_id": 21788,
                                    "title": "全新内容一览",
                                    "banner": "   ",
                                    "content_url": "",
                                }
                            ],
                        }
                    ]
                }
            }
        )

        item = converted["items"][0]
        self.assertIsNone(item["banner"])
        self.assertIsNone(item["contentURL"])

    def test_merge_official_gacha_events_merges_same_banner_with_different_start_time(self):
        snap_event = {
            "name": "镜中的茶宴",
            "type": 301,
            "version": "6.7",
            "from": "2026-07-01T06:00:00+08:00",
            "to": "2026-07-21T17:59:00+08:00",
            "banner": "https://example.com/banner.jpg",
            "upOrangeList": [10002001],
            "upPurpleList": [10000020, 10000031, 10000064],
        }
        announcements = update_remote_data.convert_official_announcements(
            {
                "data": {
                    "list": [
                        {
                            "type_label": "活动公告",
                            "list": [
                                {
                                    "ann_id": 21743,
                                    "title": "「镜中的茶宴」祈愿：「镜水析谬·桑多涅(冰)」概率UP！",
                                    "subtitle": "「镜中的茶宴」祈愿",
                                    "start_time": "2026-06-29 12:00:00",
                                    "end_time": "2026-07-21 17:59:00",
                                }
                            ],
                        }
                    ]
                }
            }
        )

        result = update_remote_data.merge_official_gacha_events(
            [snap_event],
            announcements,
            characters=[{"id": 10002001, "name": "桑多涅"}],
            weapons=[],
        )

        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["version"], "6.7")
        self.assertEqual(result[0]["upPurpleList"], [10000020, 10000031, 10000064])

    def test_normalize_announcement_feed_preserves_official_schema(self):
        normalized = update_remote_data.normalize_announcement_feed(
            {
                "schemaVersion": 1,
                "updatedAt": "2026-07-10T00:00:00Z",
                "items": [
                    {
                        "id": "7",
                        "title": "测试公告",
                        "banner": "   ",
                        "contentURL": " https://www.mihoyo.com/notice/7 ",
                        "startTime": "2026-07-10 10:00:00",
                        "endTime": "2026-07-11 10:00:00",
                        "type": "活动公告",
                    }
                ],
            }
        )

        item = normalized["items"][0]
        self.assertIsNone(item["banner"])
        self.assertEqual(item["contentURL"], "https://www.mihoyo.com/notice/7")
        self.assertEqual(item["startTime"], "2026-07-10 10:00:00")
        self.assertEqual(item["type"], "活动公告")
        self.assertNotIn("url", item)
        self.assertNotIn("startsAt", item)

    def test_announcement_validation_requires_swift_decodable_contract(self):
        with self.assertRaisesRegex(RuntimeError, "schemaVersion"):
            update_remote_data.validate_announcement_feed({"items": []})

        with self.assertRaisesRegex(RuntimeError, "updatedAt"):
            update_remote_data.validate_announcement_feed(
                {"schemaVersion": 1, "updatedAt": "not-a-date", "items": []}
            )

        with self.assertRaisesRegex(RuntimeError, "updatedAt"):
            update_remote_data.validate_announcement_feed(
                {"schemaVersion": 1, "updatedAt": "2026-07-10", "items": []}
            )

        with self.assertRaisesRegex(RuntimeError, "items\[0\]\.id"):
            update_remote_data.validate_announcement_feed(
                {
                    "schemaVersion": 1,
                    "updatedAt": "2026-07-10T00:00:00Z",
                    "items": [{"id": 7, "title": "测试公告"}],
                }
            )

    def test_repository_public_announcements_pass_current_validator(self):
        repository_root = MODULE_PATH.parents[1]
        feed = update_remote_data.read_json(repository_root / "data/public/announcements.json")
        update_remote_data.validate_announcement_feed(feed)

    def test_existing_public_data_validation_rejects_unexpected_member(self):
        with tempfile.TemporaryDirectory() as temporary:
            public = Path(temporary) / "public"
            update_remote_data.generate_public_data(self.make_payload(), public, "")
            (public / "metadata 2.json").write_text("{}\n", encoding="utf-8")

            with self.assertRaisesRegex(RuntimeError, "members mismatch"):
                update_remote_data.validate_existing_public_data(public)

    def test_repository_public_directory_passes_release_validation(self):
        repository_root = MODULE_PATH.parents[1]
        update_remote_data.validate_existing_public_data(repository_root / "data/public")

    def test_public_data_validation_rejects_empty_announcement_url(self):
        with tempfile.TemporaryDirectory() as temporary:
            public = Path(temporary) / "public"
            generated = update_remote_data.generate_public_data(self.make_payload(), public, "")
            announcements_path = public / "announcements.json"
            announcements = update_remote_data.read_json(announcements_path)
            announcements["items"] = [{"id": "1", "title": "测试公告", "url": ""}]
            update_remote_data.write_json(announcements_path, announcements)

            with self.assertRaisesRegex(RuntimeError, "announcement url"):
                update_remote_data.validate_public_data(public, generated)

    def test_managed_cache_validation_rejects_workspace_and_dot(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary).resolve()
            with self.assertRaises(RuntimeError):
                update_remote_data.validate_managed_cache_path(
                    workspace,
                    workspace,
                    update_remote_data.SNAP_METADATA_REPO_URL,
                )

            previous = Path.cwd()
            try:
                os.chdir(workspace)
                with self.assertRaises(RuntimeError):
                    update_remote_data.validate_managed_cache_path(
                        Path("."),
                        workspace,
                        update_remote_data.SNAP_METADATA_REPO_URL,
                    )
            finally:
                os.chdir(previous)

    def test_managed_cache_requires_marker_before_destructive_update(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary).resolve()
            cache = workspace / ".cache" / "Snap.Metadata"
            cache.mkdir(parents=True)
            subprocess.run(["git", "init", "-q"], cwd=cache, check=True)
            subprocess.run(
                ["git", "remote", "add", "origin", update_remote_data.SNAP_METADATA_REPO_URL],
                cwd=cache,
                check=True,
            )

            with self.assertRaises(RuntimeError):
                update_remote_data.validate_managed_cache_path(
                    cache,
                    workspace,
                    update_remote_data.SNAP_METADATA_REPO_URL,
                )

            (cache / update_remote_data.MANAGED_CACHE_MARKER).write_text("managed\n", encoding="utf-8")
            self.assertEqual(
                update_remote_data.validate_managed_cache_path(
                    cache,
                    workspace,
                    "https://github.com/SnapHutaoRemasteringProject/Snap.Metadata/",
                ),
                cache,
            )

    def test_managed_cache_rejects_mismatched_origin_before_destructive_update(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary).resolve()
            cache = workspace / ".cache" / "Snap.Metadata"
            cache.mkdir(parents=True)
            subprocess.run(["git", "init", "-q"], cwd=cache, check=True)
            subprocess.run(
                ["git", "remote", "add", "origin", "https://github.com/example/not-snap-metadata.git"],
                cwd=cache,
                check=True,
            )
            (cache / update_remote_data.MANAGED_CACHE_MARKER).write_text("managed\n", encoding="utf-8")

            previous = Path.cwd()
            try:
                os.chdir(workspace)
                with mock.patch.object(update_remote_data, "run") as run:
                    with self.assertRaisesRegex(RuntimeError, "origin"):
                        update_remote_data.ensure_git_checkout(
                            update_remote_data.SNAP_METADATA_REPO_URL,
                            cache,
                            skip_fetch=False,
                            workspace=workspace,
                        )
                    run.assert_not_called()
            finally:
                os.chdir(previous)

    def test_git_remote_normalization_accepts_dot_git_and_trailing_slash(self):
        expected = "https://github.com/SnapHutaoRemasteringProject/Snap.Metadata"
        self.assertEqual(
            update_remote_data.normalize_git_remote(f"{expected}.git/"),
            update_remote_data.normalize_git_remote(expected),
        )

    def test_existing_unmarked_checkout_is_not_adopted_before_hard_reset(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary).resolve()
            cache = workspace / ".cache" / "Snap.Metadata"
            cache.mkdir(parents=True)
            subprocess.run(["git", "init", "-q"], cwd=cache, check=True)
            subprocess.run(
                ["git", "remote", "add", "origin", update_remote_data.SNAP_METADATA_REPO_URL],
                cwd=cache,
                check=True,
            )

            previous = Path.cwd()
            try:
                os.chdir(workspace)
                with mock.patch.object(update_remote_data, "run") as run:
                    with self.assertRaises(RuntimeError):
                        update_remote_data.ensure_git_checkout(
                            update_remote_data.SNAP_METADATA_REPO_URL,
                            cache,
                            skip_fetch=False,
                            workspace=workspace,
                        )
                    run.assert_not_called()
            finally:
                os.chdir(previous)

            self.assertFalse((cache / update_remote_data.MANAGED_CACHE_MARKER).exists())

    def test_commit_rejects_unrelated_pre_staged_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repository, check=True)
            (repository / "unrelated.txt").write_text("staged", encoding="utf-8")
            public = repository / "data" / "public"
            public.mkdir(parents=True)
            (public / "metadata.json").write_text("{}", encoding="utf-8")
            subprocess.run(["git", "add", "unrelated.txt"], cwd=repository, check=True)

            previous = Path.cwd()
            try:
                os.chdir(repository)
                with self.assertRaises(RuntimeError):
                    update_remote_data.commit_and_push([public], "test")
            finally:
                os.chdir(previous)

            staged = subprocess.run(
                ["git", "diff", "--cached", "--name-only"],
                cwd=repository,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.splitlines()
            self.assertEqual(staged, ["unrelated.txt"])

    def test_second_push_sends_commit_left_ahead_after_first_push_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / "repository"
            remote = root / "remote.git"
            missing_remote = root / "missing.git"
            repository.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repository, check=True)
            subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repository, check=True)
            public = repository / "data" / "public"
            public.mkdir(parents=True)
            metadata = public / "metadata.json"
            metadata.write_text('{"version":"old"}\n', encoding="utf-8")
            subprocess.run(["git", "add", "data/public/metadata.json"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=repository, check=True)
            subprocess.run(["git", "remote", "add", "origin", str(remote)], cwd=repository, check=True)
            subprocess.run(["git", "push", "-q", "-u", "origin", "main"], cwd=repository, check=True)

            metadata.write_text('{"version":"new"}\n', encoding="utf-8")
            subprocess.run(["git", "remote", "set-url", "origin", str(missing_remote)], cwd=repository, check=True)
            previous = Path.cwd()
            try:
                os.chdir(repository)
                with self.assertRaises(subprocess.CalledProcessError):
                    update_remote_data.commit_and_push([public], "update")
                subprocess.run(["git", "remote", "set-url", "origin", str(remote)], cwd=repository, check=True)
                update_remote_data.commit_and_push([public], "update")
            finally:
                os.chdir(previous)

            published = subprocess.run(
                ["git", "--git-dir", str(remote), "show", "main:data/public/metadata.json"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            self.assertEqual(published, '{"version":"new"}\n')

    def test_generate_public_data_write_failure_preserves_existing_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            public = Path(temporary) / "public"
            public.mkdir()
            (public / "metadata.json").write_text('{"version":"old"}\n', encoding="utf-8")
            (public / "keep.txt").write_text("keep\n", encoding="utf-8")
            before = {path.name: path.read_bytes() for path in public.iterdir()}
            real_write_json = update_remote_data.write_json

            def failing_write(path: Path, value: object) -> None:
                if path.name == "characters.json":
                    raise OSError("injected JSON write failure")
                real_write_json(path, value)

            with mock.patch.object(update_remote_data, "write_json", side_effect=failing_write):
                with self.assertRaisesRegex(OSError, "injected"):
                    update_remote_data.generate_public_data(self.make_payload(), public, "")

            after = {path.name: path.read_bytes() for path in public.iterdir()}
            self.assertEqual(after, before)

    def test_generate_public_data_validation_failure_preserves_existing_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            public = Path(temporary) / "public"
            public.mkdir()
            (public / "metadata.json").write_text('{"version":"old"}\n', encoding="utf-8")
            before = {path.name: path.read_bytes() for path in public.iterdir()}

            with mock.patch.object(
                update_remote_data,
                "validate_public_data",
                side_effect=RuntimeError("injected validation failure"),
                create=True,
            ):
                with self.assertRaisesRegex(RuntimeError, "injected"):
                    update_remote_data.generate_public_data(self.make_payload(), public, "")

            after = {path.name: path.read_bytes() for path in public.iterdir()}
            self.assertEqual(after, before)

    def test_generate_public_data_replace_failure_restores_existing_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            public = Path(temporary) / "public"
            public.mkdir()
            (public / "metadata.json").write_text('{"version":"old"}\n', encoding="utf-8")
            (public / "keep.txt").write_text("keep\n", encoding="utf-8")
            before = {path.name: path.read_bytes() for path in public.iterdir()}
            real_replace = os.replace
            replace_count = 0

            def fail_publish_replace(source: Path, destination: Path) -> None:
                nonlocal replace_count
                replace_count += 1
                if replace_count == 2:
                    raise OSError("injected directory replace failure")
                real_replace(source, destination)

            with mock.patch.object(update_remote_data.os, "replace", side_effect=fail_publish_replace):
                with self.assertRaisesRegex(OSError, "injected"):
                    update_remote_data.generate_public_data(self.make_payload(), public, "")

            after = {path.name: path.read_bytes() for path in public.iterdir()}
            self.assertEqual(after, before)

    def test_package_release_failure_preserves_existing_zip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            public = root / "public"
            release = root / "release"
            generated = update_remote_data.generate_public_data(self.make_payload(), public, "")
            manifest = update_remote_data.read_json(public / "manifest.json")
            stamp = manifest["generatedAt"][:10].replace("-", ".")
            release.mkdir()
            target = release / f"data-pack-{stamp}.zip"
            target.write_bytes(b"old zip")

            with mock.patch.object(zipfile.ZipFile, "writestr", side_effect=OSError("injected ZIP write failure")):
                with self.assertRaisesRegex(OSError, "injected"):
                    update_remote_data.package_release(public, release, generated)

            self.assertEqual(target.read_bytes(), b"old zip")

    def test_package_release_validation_failure_preserves_existing_zip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            public = root / "public"
            release = root / "release"
            generated = update_remote_data.generate_public_data(self.make_payload(), public, "")
            manifest = update_remote_data.read_json(public / "manifest.json")
            stamp = manifest["generatedAt"][:10].replace("-", ".")
            release.mkdir()
            target = release / f"data-pack-{stamp}.zip"
            target.write_bytes(b"old zip")

            with mock.patch.object(
                update_remote_data,
                "validate_release_archive",
                side_effect=RuntimeError("injected ZIP validation failure"),
            ):
                with self.assertRaisesRegex(RuntimeError, "injected"):
                    update_remote_data.package_release(public, release, generated)

            self.assertEqual(target.read_bytes(), b"old zip")
            self.assertEqual(list(release.iterdir()), [target])

    def test_failed_announcement_fetch_preserves_current_nonempty_feed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manual_dir = root / "manual"
            public_dir = root / "public"
            manual_dir.mkdir()
            public_dir.mkdir()
            (manual_dir / "announcements.json").write_text(
                json.dumps({"schemaVersion": 1, "updatedAt": "2026-01-01T00:00:00Z", "items": []}),
                encoding="utf-8",
            )
            current = {
                "schemaVersion": 1,
                "updatedAt": "2026-07-10T00:00:00Z",
                "items": [{"id": "current", "title": "当前公告"}],
            }
            (public_dir / "announcements.json").write_text(json.dumps(current), encoding="utf-8")

            with mock.patch.object(update_remote_data, "fetch_official_announcements_json_if_available", return_value=None):
                selected = update_remote_data.load_announcements(
                    manual_dir,
                    official_announcements_json=None,
                    fetch_official_announcements=True,
                    current_public_announcements=public_dir / "announcements.json",
                )

            self.assertEqual(selected["items"], current["items"])

    def test_weapon_conversion_preserves_exact_ascension_stages(self):
        with tempfile.TemporaryDirectory() as temporary:
            weapon_dir = Path(temporary)
            costs = {
                f"ascend{index}": [
                    {"id": 202, "name": "摩拉", "count": index * 10000},
                    {"id": 114000 + index, "name": f"材料 {index}", "count": index + 4},
                ]
                for index in range(1, 7)
            }
            (weapon_dir / "weapon.json").write_text(
                json.dumps(
                    {
                        "id": 11509,
                        "name": "雾切之回光",
                        "weaponText": "单手剑",
                        "rarity": 5,
                        "mainStatText": "暴击伤害",
                        "costs": costs,
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            weapons = update_remote_data.convert_genshin_db_weapons(weapon_dir, {})

            self.assertEqual([stage["breakpoint"] for stage in weapons[0]["ascensionStages"]], [20, 40, 50, 60, 70, 80])
            self.assertEqual(weapons[0]["ascensionStages"][0]["costs"][1], {"materialName": "材料 1", "count": 5})

    def test_failed_fetch_without_any_nonempty_announcement_source_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            manual_dir = Path(temporary)
            (manual_dir / "announcements.json").write_text(
                json.dumps({"schemaVersion": 1, "updatedAt": "2026-01-01T00:00:00Z", "items": []}),
                encoding="utf-8",
            )

            with mock.patch.object(update_remote_data, "fetch_official_announcements_json_if_available", return_value=None):
                with self.assertRaises(RuntimeError):
                    update_remote_data.load_announcements(
                        manual_dir,
                        official_announcements_json=None,
                        fetch_official_announcements=True,
                    )


if __name__ == "__main__":
    unittest.main()
