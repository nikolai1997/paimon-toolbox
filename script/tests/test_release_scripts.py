import json
import os
import plistlib
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INSTALL_SCRIPT = ROOT / "script" / "install_app.sh"

APP_BUNDLE_ID = "com.nikolai.paimon-toolbox"
WIDGET_BUNDLE_ID = "com.nikolai.paimon-toolbox.widgets"
LEGACY_APP_BUNDLE_ID = "com.nikolai.genshin-toolbox"
LEGACY_WIDGET_BUNDLE_ID = "com.nikolai.genshin-toolbox.widgets"


FAKE_COMMAND = r'''#!/usr/bin/env python3
import json
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

name = Path(sys.argv[0]).name
args = sys.argv[1:]
events_path = Path(os.environ["PAIMON_TEST_EVENTS"])
registry_path = Path(os.environ["PAIMON_TEST_PLUGIN_REGISTRY"])
failure = os.environ.get("PAIMON_TEST_FAILURE", "")


def log(*parts):
    with events_path.open("a", encoding="utf-8") as handle:
        handle.write(" ".join(str(part) for part in parts) + "\n")


def app_for(path):
    candidate = Path(path)
    if candidate.suffix == ".appex":
        return candidate.parents[2]
    return candidate


def marker(path):
    marker_path = app_for(path) / "Contents" / "build.txt"
    return marker_path.read_text(encoding="utf-8").strip() if marker_path.exists() else "missing"


def bundle_id(path):
    plist_path = Path(path) / "Contents" / "Info.plist"
    with plist_path.open("rb") as handle:
        return plistlib.load(handle)["CFBundleIdentifier"]


def load_registry():
    if not registry_path.exists():
        return {}
    return json.loads(registry_path.read_text(encoding="utf-8"))


def save_registry(registry):
    registry_path.write_text(json.dumps(registry), encoding="utf-8")


if name == "hdiutil":
    log(name, *args)
    if args[0] == "attach":
        mountpoint = Path(args[args.index("-mountpoint") + 1])
        source = Path(os.environ["PAIMON_TEST_SOURCE_APP"])
        shutil.copytree(source, mountpoint / "PaimonToolbox.app")
    sys.exit(0)

if name == "ditto":
    source, destination = Path(args[-2]), Path(args[-1])
    log(name, marker(source), source, destination)
    shutil.copytree(source, destination)
    sys.exit(0)

if name in {"codesign", "xattr"}:
    log(name, marker(args[-1]), *args)
    sys.exit(0)

if name == "plutil":
    with Path(args[-1]).open("rb") as handle:
        print(plistlib.load(handle)["CFBundleIdentifier"])
    sys.exit(0)

if name == "pkill":
    log(name, args[-1])
    sys.exit(0)

if name == "sleep":
    log(name, *args)
    sys.exit(0)

if name == "mv":
    source, destination = Path(args[-2]), Path(args[-1])
    log(name, marker(source), source, destination)
    if failure == "rollback_move" and source.name == "PaimonToolbox.previous.app":
        sys.exit(71)
    result = subprocess.run(["/bin/mv", *args], check=False)
    sys.exit(result.returncode)

if name == "lsregister":
    action, path = args[0], Path(args[-1])
    log(name, action, marker(path), path)
    if failure == "lsregister" and action == "-f" and marker(path) == "new":
        sys.exit(72)
    sys.exit(0)

if name == "open":
    path = Path(args[-1])
    log(name, marker(path), path)
    if failure == "open" and marker(path) == "new":
        sys.exit(73)
    sys.exit(0)

if name == "pluginkit":
    registry = load_registry()
    if "-a" in args:
        path = str(Path(args[-1]))
        identifier = bundle_id(path)
        log(name, "add", marker(path), identifier, path)
        registry.setdefault(identifier, [])
        if path not in registry[identifier]:
            registry[identifier].append(path)
        save_registry(registry)
        sys.exit(0)
    if "-r" in args:
        path = str(Path(args[-1]))
        log(name, "remove", marker(path), path)
        for paths in registry.values():
            if path in paths:
                paths.remove(path)
        save_registry(registry)
        sys.exit(0)
    identifier = args[args.index("-i") + 1]
    paths = [path for path in registry.get(identifier, []) if Path(path).exists()]
    log(name, "query", identifier, *paths)
    if failure in {"widget", "rollback_move"} and identifier == os.environ["PAIMON_TEST_WIDGET_ID"]:
        if any(marker(path) == "new" for path in paths):
            print("(no matches)")
            sys.exit(0)
    if not paths:
        print("(no matches)")
    else:
        for path in paths:
            print(f"+\t{path}")
    sys.exit(0)

raise SystemExit(f"unexpected fake command: {name}")
'''


class InstallerSandbox:
    def __init__(self, failure=""):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name).resolve()
        self.install_dir = self.root / "Applications"
        self.install_dir.mkdir()
        self.home = self.root / "home"
        self.support_file = self.home / "Library" / "Application Support" / "原神工具箱" / "account.json"
        self.support_file.parent.mkdir(parents=True)
        self.support_file.write_text("user-data", encoding="utf-8")
        self.source_app = self.root / "source" / "PaimonToolbox.app"
        self.old_app = self.install_dir / "PaimonToolbox.app"
        self.legacy_app = self.install_dir / "GenshinToolbox.app"
        self._make_app(
            self.source_app,
            "PaimonToolbox",
            APP_BUNDLE_ID,
            "PaimonToolboxWidgetsExtension",
            WIDGET_BUNDLE_ID,
            "new",
        )
        self._make_app(
            self.old_app,
            "PaimonToolbox",
            APP_BUNDLE_ID,
            "PaimonToolboxWidgetsExtension",
            WIDGET_BUNDLE_ID,
            "old-paimon",
        )
        self._make_app(
            self.legacy_app,
            "GenshinToolbox",
            LEGACY_APP_BUNDLE_ID,
            "GenshinToolboxWidgetsExtension",
            LEGACY_WIDGET_BUNDLE_ID,
            "old-genshin",
        )

        self.events = self.root / "events.log"
        self.events.touch()
        self.registry = self.root / "plugins.json"
        self.registry.write_text(
            json.dumps(
                {
                    WIDGET_BUNDLE_ID: [str(self.widget_path(self.old_app, "PaimonToolboxWidgetsExtension"))],
                    LEGACY_WIDGET_BUNDLE_ID: [str(self.widget_path(self.legacy_app, "GenshinToolboxWidgetsExtension"))],
                }
            ),
            encoding="utf-8",
        )
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        command = self.bin_dir / "fake-command"
        command.write_text(FAKE_COMMAND, encoding="utf-8")
        command.chmod(command.stat().st_mode | stat.S_IXUSR)
        for name in (
            "codesign",
            "ditto",
            "hdiutil",
            "lsregister",
            "mv",
            "open",
            "pkill",
            "pluginkit",
            "plutil",
            "sleep",
            "xattr",
        ):
            (self.bin_dir / name).symlink_to(command)
        self.package_script = self.root / "package.sh"
        self.package_script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.package_script.chmod(self.package_script.stat().st_mode | stat.S_IXUSR)
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "PATH": f"{self.bin_dir}:{self.env['PATH']}",
                "PAIMON_INSTALL_LSREGISTER": str(self.bin_dir / "lsregister"),
                "PAIMON_INSTALL_PACKAGE_SCRIPT": str(self.package_script),
                "PAIMON_INSTALL_VERIFY_DELAY": "0",
                "PAIMON_TEST_EVENTS": str(self.events),
                "PAIMON_TEST_FAILURE": failure,
                "PAIMON_TEST_PLUGIN_REGISTRY": str(self.registry),
                "PAIMON_TEST_SOURCE_APP": str(self.source_app),
                "PAIMON_TEST_WIDGET_ID": WIDGET_BUNDLE_ID,
                "TMPDIR": str(self.root),
            }
        )

    @staticmethod
    def widget_path(app, extension_name):
        return app / "Contents" / "PlugIns" / f"{extension_name}.appex"

    def _make_app(self, path, executable, app_id, extension, widget_id, marker):
        widget = self.widget_path(path, extension)
        binary = path / "Contents" / "MacOS" / executable
        (widget / "Contents").mkdir(parents=True)
        binary.parent.mkdir(parents=True, exist_ok=True)
        with (path / "Contents" / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleIdentifier": app_id}, handle)
        with (widget / "Contents" / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleIdentifier": widget_id}, handle)
        (path / "Contents" / "build.txt").write_text(marker, encoding="utf-8")
        binary.write_text(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                echo "self-check {marker}" >> "$PAIMON_TEST_EVENTS"
                exit 0
                """
            ),
            encoding="utf-8",
        )
        binary.chmod(binary.stat().st_mode | stat.S_IXUSR)

    def run(self):
        source = INSTALL_SCRIPT.read_text(encoding="utf-8")
        if "PAIMON_INSTALL_PACKAGE_SCRIPT" not in source:
            raise AssertionError("installer must expose PAIMON_INSTALL_PACKAGE_SCRIPT for transaction tests")
        return subprocess.run(
            [str(INSTALL_SCRIPT), str(self.install_dir)],
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def marker(self, app):
        return (app / "Contents" / "build.txt").read_text(encoding="utf-8").strip()

    def log(self):
        return self.events.read_text(encoding="utf-8").splitlines()

    def close(self):
        self.temp_dir.cleanup()


class ReleaseScriptTests(unittest.TestCase):
    def test_install_supports_injected_transaction_dependencies(self):
        source = INSTALL_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("PAIMON_INSTALL_PACKAGE_SCRIPT", source)
        self.assertIn("PAIMON_INSTALL_LSREGISTER", source)
        self.assertIn("PAIMON_INSTALL_VERIFY_DELAY", source)

    def test_install_validates_staged_app_before_replacing_destination(self):
        source = INSTALL_SCRIPT.read_text(encoding="utf-8")

        staged = source.index("STAGED_APP=")
        verify = source.index('codesign --verify --deep --strict "$STAGED_APP"')
        app_id = source.index("APP_BUNDLE_ID", verify)
        widget_id = source.index("WIDGET_BUNDLE_ID", verify)
        self_check = source.index('"$STAGED_APP/Contents/MacOS/$APP_NAME" --self-check')
        replace = source.index('mv "$STAGED_APP" "$DEST_APP"')
        self.assertLess(staged, verify)
        self.assertLess(verify, app_id)
        self.assertLess(app_id, replace)
        self.assertLess(widget_id, replace)
        self.assertLess(self_check, replace)
        self.assertNotIn('rm -rf "$DEST_APP"', source)
        self.assertIn("restore_previous_install", source)

    def test_success_migrates_legacy_app_only_after_new_widget_verification(self):
        sandbox = InstallerSandbox()
        self.addCleanup(sandbox.close)

        result = sandbox.run()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sandbox.marker(sandbox.old_app), "new")
        self.assertFalse(sandbox.legacy_app.exists())
        self.assertTrue(sandbox.support_file.exists())
        self.assertEqual(list(sandbox.install_dir.glob(".PaimonToolbox.install.*")), [])
        events = sandbox.log()
        self_check = events.index("self-check new")
        stopped_current = events.index("pkill PaimonToolbox")
        stopped_legacy = events.index("pkill GenshinToolbox")
        current_move = next(i for i, line in enumerate(events) if line.startswith("mv old-paimon"))
        widget_query = next(i for i, line in enumerate(events) if line.startswith(f"pluginkit query {WIDGET_BUNDLE_ID}"))
        legacy_unregister = next(i for i, line in enumerate(events) if "lsregister -u old-genshin" in line)
        legacy_move = next(i for i, line in enumerate(events) if line.startswith("mv old-genshin"))
        self.assertLess(self_check, stopped_current)
        self.assertLess(stopped_current, current_move)
        self.assertLess(stopped_legacy, legacy_move)
        self.assertLess(widget_query, legacy_unregister)
        self.assertLess(legacy_unregister, legacy_move)

    def test_final_install_failures_restore_and_reregister_previous_apps(self):
        for failure in ("lsregister", "open", "widget"):
            with self.subTest(failure=failure):
                sandbox = InstallerSandbox(failure)
                try:
                    result = sandbox.run()

                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(sandbox.marker(sandbox.old_app), "old-paimon")
                    self.assertEqual(sandbox.marker(sandbox.legacy_app), "old-genshin")
                    self.assertTrue(sandbox.support_file.exists())
                    self.assertEqual(list(sandbox.install_dir.glob(".PaimonToolbox.install.*")), [])
                    events = sandbox.log()
                    failure_index = next(
                        i
                        for i, line in enumerate(events)
                        if (failure == "lsregister" and "lsregister -f new" in line)
                        or (failure == "open" and line.startswith("open new"))
                        or (failure == "widget" and line.startswith(f"pluginkit query {WIDGET_BUNDLE_ID}"))
                    )
                    after_failure = events[failure_index + 1 :]
                    self.assertIn("pkill PaimonToolbox", after_failure)
                    stopped_new = events.index("pkill PaimonToolbox", failure_index + 1)
                    restored_ls_line = next(
                        (line for line in events[stopped_new + 1 :] if "lsregister -f old-paimon" in line),
                        None,
                    )
                    self.assertIsNotNone(restored_ls_line)
                    restored_ls = events.index(restored_ls_line, stopped_new + 1)
                    restored_widget_line = next(
                        (
                            line
                            for line in events[restored_ls + 1 :]
                            if f"pluginkit add old-paimon {WIDGET_BUNDLE_ID}" in line
                        ),
                        None,
                    )
                    self.assertIsNotNone(restored_widget_line)
                    restored_widget = events.index(restored_widget_line, restored_ls + 1)
                    legacy_ls_line = next(
                        (line for line in events[restored_widget + 1 :] if "lsregister -f old-genshin" in line),
                        None,
                    )
                    self.assertIsNotNone(legacy_ls_line)
                    legacy_ls = events.index(legacy_ls_line, restored_widget + 1)
                    legacy_widget_line = next(
                        (
                            line
                            for line in events[legacy_ls + 1 :]
                            if f"pluginkit add old-genshin {LEGACY_WIDGET_BUNDLE_ID}" in line
                        ),
                        None,
                    )
                    self.assertIsNotNone(legacy_widget_line)
                    legacy_widget = events.index(legacy_widget_line, legacy_ls + 1)
                    self.assertLess(stopped_new, restored_ls)
                    self.assertLess(restored_ls, restored_widget)
                    self.assertLess(restored_widget, legacy_ls)
                    self.assertLess(legacy_ls, legacy_widget)
                finally:
                    sandbox.close()

    def test_failed_restore_keeps_backup_and_reports_transaction_path(self):
        sandbox = InstallerSandbox("rollback_move")
        self.addCleanup(sandbox.close)

        result = sandbox.run()

        self.assertNotEqual(result.returncode, 0)
        work_dirs = list(sandbox.install_dir.glob(".PaimonToolbox.install.*"))
        self.assertEqual(len(work_dirs), 1)
        backup = work_dirs[0] / "PaimonToolbox.previous.app"
        self.assertTrue(backup.exists())
        self.assertEqual(sandbox.marker(backup), "old-paimon")
        self.assertIn(str(work_dirs[0]), result.stderr)
        self.assertIn("recovery failed", result.stderr.lower())
        self.assertTrue(sandbox.support_file.exists())

    def test_dmg_is_verified_before_atomic_final_replacement(self):
        source = (ROOT / "script" / "package_dmg.sh").read_text(encoding="utf-8")

        verify = source.index('hdiutil verify "$TMP_DMG_PATH"')
        replace = source.index('mv -f "$TMP_DMG_PATH" "$DMG_PATH"')
        self.assertLess(verify, replace)
        self.assertNotIn('rm -rf "$DMG_PATH"', source)

    def test_widget_verification_compares_canonical_bundle_path(self):
        source = (ROOT / "script" / "build_and_run.sh").read_text(encoding="utf-8")

        self.assertIn('PLUGIN_EXTENSION_PATH="$(cd "$(dirname "$EXTENSION_BUNDLE")" && pwd -P)/$(basename "$EXTENSION_BUNDLE")"', source)
        self.assertIn("$PLUGIN_EXTENSION_PATH", source)


if __name__ == "__main__":
    unittest.main()
