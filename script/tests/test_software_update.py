import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mirror_software_release as mirror
import prepare_software_update as updates


class SoftwareUpdateTests(unittest.TestCase):
    def release(self):
        return {"id": 1, "tag_name": "v0.1.6", "draft": False, "prerelease": False,
                "assets": [{"id": 2, "name": "PaimonToolbox-0.1.6.dmg", "size": 3,
                            "digest": "sha256:" + hashlib.sha256(b"dmg").hexdigest(),
                            "browser_download_url": "https://github.com/nikolai1997/paimon-toolbox/releases/download/v0.1.6/PaimonToolbox-0.1.6.dmg"}]}

    def test_mirror_selects_matching_software_package_not_data_pack(self):
        release = self.release()
        release["assets"].append({"name": "data-pack-2026.11.10.zip"})
        package, feed = mirror.release_assets(release)
        self.assertEqual(package["name"], "PaimonToolbox-0.1.6.dmg")
        self.assertIsNone(feed)

    def test_mirror_rejects_preview_release_missing_hash_or_wrong_version(self):
        for change in ["preview", "hash", "version"]:
            release = self.release()
            if change == "preview": release["prerelease"] = True
            elif change == "hash": release["assets"][0].pop("digest")
            else: release["tag_name"] = "v0.1.7"
            with self.subTest(change=change), self.assertRaises(ValueError):
                mirror.release_assets(release)

    def test_download_checks_real_bytes_against_github_digest(self):
        asset = self.release()["assets"][0]
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "package.dmg"
            with mock.patch.object(mirror.urllib.request, "urlopen", return_value=io.BytesIO(b"bad")):
                with self.assertRaisesRegex(ValueError, "SHA-256"):
                    mirror.download_asset(asset, output)
            with mock.patch.object(mirror.urllib.request, "urlopen", return_value=io.BytesIO(b"dmg")):
                mirror.download_asset(asset, output)
                self.assertEqual(output.read_bytes(), b"dmg")

    def test_upload_credentials_are_not_followed_to_a_redirect(self):
        response = mock.Mock(status=302)
        response.read.return_value = b""
        connection = mock.Mock()
        connection.getresponse.return_value = response
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "package.dmg"
            package.write_bytes(b"dmg")
            with mock.patch.object(mirror.http.client, "HTTPSConnection", return_value=connection) as connect:
                dav = mirror.WebDAV("https://dav.jianguoyun.com/dav/SoftwareUpdates", "test-account", "test-password")
                with self.assertRaisesRegex(RuntimeError, "HTTP 302"):
                    dav.upload(package, package.name)
                connect.assert_called_once_with("dav.jianguoyun.com", None, timeout=180)

    def test_upload_retries_network_errors_with_a_fresh_file_stream(self):
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "package.dmg"
            package.write_bytes(b"dmg")
            dav = mirror.WebDAV("https://dav.jianguoyun.com/dav/SoftwareUpdates", "test-account", "test-password")
            attempts = []
            def send(method, name, body, size):
                attempts.append(body.read())
                if len(attempts) == 1:
                    raise TimeoutError()
                return 201, b""
            with mock.patch.object(dav, "send", side_effect=send), mock.patch.object(mirror.time, "sleep"):
                dav.upload(package, "package.dmg")
            self.assertEqual(attempts, [b"dmg", b"dmg"])

    def test_alias_uses_server_copy_and_only_falls_back_if_unsupported(self):
        dav = mirror.WebDAV("https://dav.jianguoyun.com/dav/SoftwareUpdates", "test-account", "test-password")
        package = Path("package.dmg")
        with mock.patch.object(dav, "send", return_value=(201, b"")) as send, mock.patch.object(dav, "upload") as upload:
            dav.upload_alias(package, "package.dmg", "latest.dmg")
            self.assertEqual(send.call_args.kwargs["extra_headers"]["Destination"],
                             "https://dav.jianguoyun.com/dav/SoftwareUpdates/latest.dmg")
            upload.assert_not_called()
        with mock.patch.object(dav, "send", return_value=(405, b"")), mock.patch.object(dav, "upload") as upload:
            dav.upload_alias(package, "package.dmg", "latest.dmg")
            upload.assert_called_once_with(package, "latest.dmg")

    def test_update_addresses_reject_embedded_credentials(self):
        for url in ["http://example.com/", "https://account:password@example.com/", "file:///tmp/"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                updates.public_url(url)

    def test_feed_must_match_signed_package_version_size_and_download_address(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            package = root / "PaimonToolbox-0.1.6.dmg"
            package.write_bytes(b"dmg")
            feed = root / "appcast.xml"
            signature = base64.b64encode(bytes(64)).decode()
            prefix = "https://example.com/releases/"
            content = f'''<rss xmlns:sparkle="{updates.SPARKLE_NS}"><channel><item>
            <sparkle:version>0.1.6</sparkle:version><enclosure url="{prefix}{package.name}"
            length="3" sparkle:edSignature="{signature}"/></item></channel></rss>'''
            feed.write_text(content)
            updates.validate_feed(feed, package, "0.1.6", prefix)
            for bad in [content.replace('length="3"', 'length="4"'),
                        content.replace("<sparkle:version>0.1.6", "<sparkle:version>0.1.5"),
                        content.replace(signature, "unsigned"),
                        content.replace(prefix, "https://wrong.example.com/")]:
                feed.write_text(bad)
                with self.assertRaises((RuntimeError, ValueError)):
                    updates.validate_feed(feed, package, "0.1.6", prefix)

    def test_bundled_configuration_contains_a_public_key_and_no_upload_credentials(self):
        root = Path(__file__).resolve().parents[2]
        config = json.loads((root / "Resources/software-update.json").read_text())
        self.assertEqual(len(base64.b64decode(config["publicKey"])), 32)
        for key in config:
            self.assertNotIn("password", key.lower())
            self.assertNotIn("username", key.lower())
            self.assertNotIn("private", key.lower())


if __name__ == "__main__":
    unittest.main()
