from pathlib import Path
import sys
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cleanup_jianguoyun_data as cleanup

BASE = "https://dav.jianguoyun.com/dav/example/GenshinToolbox"


def listing(entries):
    root = ET.Element(cleanup.DAV + "multistatus")
    for href, size, collection in entries:
        response = ET.SubElement(root, cleanup.DAV + "response")
        ET.SubElement(response, cleanup.DAV + "href").text = href
        propstat = ET.SubElement(response, cleanup.DAV + "propstat")
        ET.SubElement(propstat, cleanup.DAV + "status").text = "HTTP/1.1 200 OK"
        prop = ET.SubElement(propstat, cleanup.DAV + "prop")
        ET.SubElement(prop, cleanup.DAV + "getcontentlength").text = str(size)
        resource = ET.SubElement(prop, cleanup.DAV + "resourcetype")
        if collection:
            ET.SubElement(resource, cleanup.DAV + "collection")
    return ET.tostring(root)


class JianguoyunCleanupTests(unittest.TestCase):
    def test_only_valid_dated_package_names_are_candidates(self):
        for name in ["data-pack-latest.zip", "PaimonToolbox-0.1.6.dmg", "data-pack-2026.02.30.zip", "../data-pack-2026.11.01.zip", "data-pack-2026.11.01.zip.bak"]:
            self.assertIsNone(cleanup.package_date(name))
        self.assertIsNotNone(cleanup.package_date("data-pack-2026.11.10.zip"))

    def test_retains_latest_and_seven_newest_dated_packs(self):
        entries = {f"data-pack-2026.11.{day:02}.zip": 100 for day in range(1, 11)}
        entries.update({"data-pack-latest.zip": 100, "other.zip": 100})
        self.assertEqual(cleanup.deletion_plan(entries, "data-pack-2026.11.10.zip", 100, 7),
                         ["data-pack-2026.11.03.zip", "data-pack-2026.11.02.zip", "data-pack-2026.11.01.zip"])

    def test_partial_or_stale_upload_never_allows_cleanup(self):
        entries = {"data-pack-2026.11.10.zip": 100, "data-pack-latest.zip": 100}
        for newest, size, keep in [("data-pack-2026.11.09.zip", 100, 7), ("data-pack-2026.11.10.zip", 101, 7), ("data-pack-2026.11.10.zip", 100, 0)]:
            with self.assertRaises(ValueError):
                cleanup.deletion_plan(entries, newest, size, keep)
        with self.assertRaises(ValueError):
            cleanup.deletion_plan({"data-pack-2026.11.10.zip": 100}, "data-pack-2026.11.10.zip", 100, 7)

    def test_directory_listing_cannot_escape_scope_or_delete_subfolders(self):
        good = BASE + "/data-pack-2026.11.10.zip"
        paths = [(good, 100, False), (BASE + "/data-pack-latest.zip", 100, False),
                 (BASE + "/SoftwareUpdates/data-pack-2026.11.01.zip", 100, False),
                 (BASE + "/data-pack-2026.11.02.zip", 100, True),
                 ("https://evil.example.com/dav/example/GenshinToolbox/data-pack-2026.11.03.zip", 100, False),
                 (BASE + "/%2e%2e/data-pack-2026.11.04.zip", 100, False),
                 (BASE + "/other.zip", 100, False)]
        self.assertEqual(cleanup.parse_listing(listing(paths), BASE),
                         {"data-pack-2026.11.10.zip": 100, "data-pack-latest.zip": 100})

    def test_cleanup_rejects_wrong_host_directory_and_credentials_in_urls(self):
        for base in ["http://dav.jianguoyun.com/dav/GenshinToolbox", "https://other.example.com/GenshinToolbox", "https://a:b@dav.jianguoyun.com/dav/GenshinToolbox", "https://dav.jianguoyun.com/dav/GenshinToolbox/SoftwareUpdates", "https://dav.jianguoyun.com/dav/../GenshinToolbox"]:
            with self.assertRaises(ValueError):
                cleanup.validate_base_url(base)

    def test_dry_run_does_not_issue_delete_requests(self):
        dav = cleanup.WebDAV(BASE, "fixture", "fixture")
        entries = [(BASE + "/" + name, 100, False) for name in ["data-pack-latest.zip", "data-pack-2026.11.09.zip", "data-pack-2026.11.10.zip"]]
        with mock.patch.object(dav, "request", return_value=(207, listing(entries))) as request:
            self.assertEqual(cleanup.cleanup(dav, "data-pack-2026.11.10.zip", 100, 1, False), ["data-pack-2026.11.09.zip"])
            request.assert_called_once_with("PROPFIND")

    def test_apply_deletes_only_planned_files_and_checks_result(self):
        dav = cleanup.WebDAV(BASE, "fixture", "fixture")
        names = ["data-pack-latest.zip", "data-pack-2026.11.09.zip", "data-pack-2026.11.10.zip"]
        before = listing([(BASE + "/" + name, 100, False) for name in names])
        after = listing([(BASE + "/" + name, 100, False) for name in names if "09" not in name])
        with mock.patch.object(dav, "request", side_effect=[(207, before), (204, b""), (207, after)]) as request:
            cleanup.cleanup(dav, "data-pack-2026.11.10.zip", 100, 1, True)
            self.assertEqual(request.call_args_list, [mock.call("PROPFIND"), mock.call("DELETE", "data-pack-2026.11.09.zip"), mock.call("PROPFIND")])

    def test_delete_rejects_latest_alias_and_directory_names(self):
        dav = cleanup.WebDAV(BASE, "fixture", "fixture")
        for name in ["data-pack-latest.zip", "SoftwareUpdates", "../private"]:
            with self.assertRaises(ValueError):
                dav.request("DELETE", name)

    def test_network_failure_retries_without_following_redirects(self):
        dav = cleanup.WebDAV(BASE, "fixture", "fixture")
        first = mock.Mock()
        first.request.side_effect = OSError("network interrupted")
        second = mock.Mock()
        response = second.getresponse.return_value
        response.status = 204
        response.read.return_value = b""
        with mock.patch.object(cleanup.http.client, "HTTPSConnection", side_effect=[first, second]), mock.patch.object(cleanup.time, "sleep"):
            self.assertEqual(dav.request("DELETE", "data-pack-2026.11.01.zip"), (204, b""))
        self.assertNotIn("Depth", second.request.call_args.kwargs["headers"])
        self.assertEqual(second.request.call_args.args[1], "/dav/example/GenshinToolbox/data-pack-2026.11.01.zip")
        first.close.assert_called_once()
        second.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
