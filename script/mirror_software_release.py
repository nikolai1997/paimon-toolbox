#!/usr/bin/env python3
"""Mirror the latest public software release to a private WebDAV upload account."""

import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import tempfile
import time
import urllib.parse
import urllib.request

REPOSITORY = "nikolai1997/paimon-toolbox"


def release_assets(release: dict) -> tuple[dict, dict | None]:
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Only stable published releases can be mirrored")
    tag = release.get("tag_name", "")
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Unexpected release version")
    expected = f"PaimonToolbox-{tag[1:]}.dmg"
    packages = [asset for asset in release.get("assets", []) if asset.get("name") == expected]
    if len(packages) != 1:
        raise ValueError("A matching software DMG is required")
    package = packages[0]
    if not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", package.get("digest", "")):
        raise ValueError("GitHub asset SHA-256 digest is missing")
    mirror_feed = next((asset for asset in release.get("assets", []) if asset.get("name") == "appcast-jianguoyun.xml"), None)
    return package, mirror_feed


class WebDAV:
    def __init__(self, base_url: str, username: str, password: str):
        self.url = urllib.parse.urlsplit(base_url.rstrip("/"))
        if self.url.scheme != "https" or not self.url.hostname or self.url.username or self.url.password or self.url.query:
            raise ValueError("Invalid WebDAV base URL")
        self.authorization = "Basic " + base64.b64encode(f"{username}:{password}".encode()).decode()

    def send(self, method: str, name: str = "", body=None, size: int | None = None,
             extra_headers: dict | None = None) -> tuple[int, bytes]:
        connection = http.client.HTTPSConnection(self.url.hostname, self.url.port, timeout=180)
        path = self.url.path + ("/" + urllib.parse.quote(name, safe="") if name else "")
        headers = {"Authorization": self.authorization}
        headers.update(extra_headers or {})
        if size is not None:
            headers["Content-Length"] = str(size)
        try:
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            # Do not follow redirects carrying upload credentials to another endpoint.
            return response.status, response.read(1_000_001)
        finally:
            connection.close()

    def upload(self, path: Path, name: str) -> None:
        for attempt in range(3):
            try:
                with path.open("rb") as body:
                    status, _ = self.send("PUT", name, body, path.stat().st_size)
            except (OSError, http.client.HTTPException):
                if attempt == 2:
                    raise RuntimeError("WebDAV upload failed after network retries") from None
            else:
                if status in (200, 201, 204):
                    return
                if status not in (408, 429, 500, 502, 503, 504) or attempt == 2:
                    raise RuntimeError(f"WebDAV upload failed: HTTP {status}")
            time.sleep(5 * (attempt + 1))

    def upload_alias(self, path: Path, source_name: str, alias_name: str) -> None:
        destination = urllib.parse.urlunsplit(self.url) + "/" + urllib.parse.quote(alias_name, safe="")
        try:
            status, _ = self.send("COPY", source_name,
                                  extra_headers={"Destination": destination, "Overwrite": "T"})
            if status in (201, 204):
                return
            if status not in (405, 501):
                raise RuntimeError(f"WebDAV copy failed: HTTP {status}")
        except (OSError, http.client.HTTPException):
            pass
        self.upload(path, alias_name)


def download_asset(asset: dict, destination: Path) -> None:
    url = asset.get("browser_download_url", "")
    prefix = f"https://github.com/{REPOSITORY}/releases/download/"
    if not url.startswith(prefix):
        raise ValueError("Unexpected release asset host or repository")
    expected = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[a-fA-F0-9]{64}", expected):
        raise ValueError("Release asset digest is missing")
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(url, timeout=90) as response, destination.open("wb") as target:
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > 1_000_000_000:
                raise ValueError("Release asset exceeds the size limit")
            digest.update(chunk)
            target.write(chunk)
    if size != asset.get("size") or digest.hexdigest() != expected.split(":", 1)[1].lower():
        raise ValueError("Release asset size or SHA-256 mismatch")


def main() -> None:
    username = os.environ.get("JIANGUOYUN_USERNAME", "")
    password = os.environ.get("JIANGUOYUN_APP_PASSWORD", "")
    base_url = os.environ.get("JIANGUOYUN_SOFTWARE_WEBDAV_BASE_URL", "")
    if not username or not password or not base_url:
        raise RuntimeError("Jianguoyun software upload settings are missing")
    request = urllib.request.Request(f"https://api.github.com/repos/{REPOSITORY}/releases/latest",
                                     headers={"Accept": "application/vnd.github+json", "User-Agent": "PaimonToolboxReleaseMirror"})
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    package, feed = release_assets(release)
    dav = WebDAV(base_url, username, password)
    status, _ = dav.send("MKCOL")
    if status not in (201, 405):
        raise RuntimeError(f"Cannot create software mirror directory: HTTP {status}")
    status, cached = dav.send("GET", "software-latest.json")
    fingerprint = {"releaseID": release["id"], "packageID": package["id"],
                   "sha256": package["digest"].split(":", 1)[1], "feedID": feed["id"] if feed else None}
    if status == 200:
        try:
            if json.loads(cached).get("fingerprint") == fingerprint:
                print("Software mirror is already current:", release["tag_name"])
                return
        except (ValueError, TypeError):
            pass
    elif status != 404:
        raise RuntimeError(f"Cannot check software mirror: HTTP {status}")
    with tempfile.TemporaryDirectory(prefix="paimon-software-mirror-") as temporary:
        root = Path(temporary)
        archive = root / package["name"]
        download_asset(package, archive)
        dav.upload(archive, package["name"])
        dav.upload_alias(archive, package["name"], "PaimonToolbox-latest.dmg")
        if feed:
            appcast = root / "appcast.xml"
            download_asset(feed, appcast)
            dav.upload(appcast, "appcast.xml")
        marker = root / "software-latest.json"
        marker.write_text(json.dumps({"version": release["tag_name"], "filename": package["name"],
                                      "fingerprint": fingerprint, "automaticMirrorAvailable": bool(feed)}, indent=2) + "\n")
        dav.upload(marker, marker.name)
    print("Mirrored software release:", release["tag_name"])


if __name__ == "__main__":
    main()
