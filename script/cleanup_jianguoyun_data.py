#!/usr/bin/env python3
"""Retain recent dated data packs after verifying the newly uploaded package."""

import argparse
import base64
from datetime import date
import http.client
import os
import re
import time
import urllib.parse
import xml.etree.ElementTree as ET

DAV = "{DAV:}"
PACKAGE_PATTERN = re.compile(r"data-pack-(\d{4})\.(\d{2})\.(\d{2})\.zip")


def package_date(name: str) -> date | None:
    match = PACKAGE_PATTERN.fullmatch(name)
    if not match:
        return None
    try:
        return date(*(int(part) for part in match.groups()))
    except ValueError:
        return None


def validate_base_url(value: str) -> urllib.parse.SplitResult:
    url = urllib.parse.urlsplit(value.rstrip("/"))
    path = urllib.parse.unquote(url.path)
    if (url.scheme != "https" or url.hostname != "dav.jianguoyun.com"
            or url.port not in (None, 443) or url.username or url.password
            or url.query or url.fragment or not path.endswith("/GenshinToolbox")
            or any(part in (".", "..") for part in path.split("/"))):
        raise ValueError("Cleanup is restricted to the Jianguoyun GenshinToolbox directory")
    return url


def parse_listing(content: bytes, base_url: str) -> dict[str, int]:
    base = validate_base_url(base_url)
    if len(content) > 2_000_000 or b"<!DOCTYPE" in content.upper():
        raise ValueError("Invalid WebDAV directory response")
    root = ET.fromstring(content)
    if root.tag != DAV + "multistatus":
        raise ValueError("Expected a WebDAV directory listing")
    parent = urllib.parse.unquote(base.path).rstrip("/") + "/"
    entries = {}
    for response in root.findall(DAV + "response"):
        href = response.findtext(DAV + "href", "")
        target = urllib.parse.urlsplit(urllib.parse.urljoin(base_url.rstrip("/") + "/", href))
        if (target.scheme != "https" or target.hostname != base.hostname
                or target.port not in (None, 443) or target.username or target.password
                or target.query or target.fragment):
            continue
        path = urllib.parse.unquote(target.path)
        if not path.startswith(parent):
            continue
        name = path[len(parent):]
        if "/" in name or (name != "data-pack-latest.zip" and package_date(name) is None):
            continue
        for propstat in response.findall(DAV + "propstat"):
            status = propstat.findtext(DAV + "status", "").split()
            prop = propstat.find(DAV + "prop")
            if len(status) < 2 or status[1] != "200" or prop is None:
                continue
            if prop.find(DAV + "resourcetype/" + DAV + "collection") is not None:
                continue
            length = prop.findtext(DAV + "getcontentlength", "")
            if not length.isdecimal() or int(length) <= 0:
                continue
            if name in entries:
                raise ValueError("Duplicate WebDAV package entry")
            entries[name] = int(length)
    return entries


def deletion_plan(entries: dict[str, int], newest: str, expected_size: int, keep: int) -> list[str]:
    if keep < 1 or package_date(newest) is None or expected_size <= 0:
        raise ValueError("Invalid retention or package settings")
    if entries.get(newest) != expected_size or entries.get("data-pack-latest.zip") != expected_size:
        raise ValueError("Newest package and latest alias must both match the uploaded size")
    dated = sorted((name for name in entries if package_date(name)), key=package_date, reverse=True)
    if not dated or dated[0] != newest:
        raise ValueError("The uploaded package is not the newest remote data pack")
    return dated[keep:]


class WebDAV:
    def __init__(self, base_url: str, username: str, password: str):
        self.url = validate_base_url(base_url)
        self.authorization = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()

    def request(self, method: str, name: str = "") -> tuple[int, bytes]:
        if name and package_date(name) is None:
            raise ValueError("Only dated data pack files may be deleted")
        path = self.url.path + ("/" + urllib.parse.quote(name, safe="") if name else "/")
        headers = {"Authorization": self.authorization}
        if method == "PROPFIND":
            headers["Depth"] = "1"
        for attempt in range(3):
            connection = http.client.HTTPSConnection(self.url.hostname, self.url.port, timeout=60)
            try:
                connection.request(method, path, headers=headers)
                response = connection.getresponse()
                content = response.read(2_000_001)
                if response.status not in (408, 429, 500, 502, 503, 504) or attempt == 2:
                    return response.status, content
            except (OSError, http.client.HTTPException):
                if attempt == 2:
                    raise RuntimeError("WebDAV retention request failed after network retries") from None
            finally:
                connection.close()
            time.sleep(5 * (attempt + 1))
        raise RuntimeError("WebDAV retention request did not complete")


def cleanup(dav: WebDAV, newest: str, expected_size: int, keep: int, apply: bool) -> list[str]:
    base_url = urllib.parse.urlunsplit(dav.url)
    status, content = dav.request("PROPFIND")
    if status != 207:
        raise RuntimeError(f"Cannot list data packs: HTTP {status}")
    entries = parse_listing(content, base_url)
    candidates = deletion_plan(entries, newest, expected_size, keep)
    print(f"Verified latest package; retaining {keep} dated backups; older packages: {len(candidates)}")
    if not apply:
        return candidates
    for name in candidates:
        status, _ = dav.request("DELETE", name)
        if status not in (200, 204, 404):
            raise RuntimeError(f"Cannot remove old data pack: HTTP {status}")
        print("Removed old data pack:", name)
        time.sleep(0.5)
    status, content = dav.request("PROPFIND")
    if status != 207:
        raise RuntimeError("Cannot verify data pack retention")
    remaining = parse_listing(content, base_url)
    if deletion_plan(remaining, newest, expected_size, keep):
        raise RuntimeError("Old data packs remain after cleanup")
    print("Verified data pack retention")
    return candidates


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--latest-package-name", required=True)
    parser.add_argument("--expected-size", required=True, type=int)
    parser.add_argument("--keep", type=int, default=7)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    username = os.environ.get("JIANGUOYUN_USERNAME", "")
    password = os.environ.get("JIANGUOYUN_APP_PASSWORD", "")
    base_url = os.environ.get("JIANGUOYUN_WEBDAV_BASE_URL", "")
    if not username or not password:
        raise RuntimeError("Jianguoyun upload credentials are not configured")
    cleanup(WebDAV(base_url, username, password), args.latest_package_name, args.expected_size, args.keep, args.apply)


if __name__ == "__main__":
    main()
