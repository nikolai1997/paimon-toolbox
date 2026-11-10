#!/usr/bin/env python3
"""Generate signed Sparkle feeds for an already built release DMG."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET

from fetch_sparkle import ROOT, ensure_sparkle

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
REPOSITORY = "nikolai1997/paimon-toolbox"
KEY_ACCOUNT = "com.nikolai.paimon-toolbox"


def public_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Update download address must be a public HTTPS URL without credentials")
    return value.rstrip("/") + "/"


def validate_feed(path: Path, package: Path, expected_version: str, prefix: str) -> None:
    root = ET.parse(path).getroot()
    item = root.find("./channel/item")
    if item is None:
        raise RuntimeError("Generated appcast has no update item")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise RuntimeError("Generated appcast has no update archive")
    signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise RuntimeError("Update archive has no valid Ed25519 signature")
    version = item.findtext(f"{{{SPARKLE_NS}}}version") or enclosure.get(f"{{{SPARKLE_NS}}}version")
    if version != expected_version:
        raise RuntimeError(f"Archive build version {version} does not match VERSION {expected_version}")
    if int(enclosure.get("length", "0")) != package.stat().st_size:
        raise RuntimeError("Update archive size does not match appcast")
    if enclosure.get("url") != prefix + urllib.parse.quote(package.name):
        raise RuntimeError("Unexpected update archive URL in appcast")


def prepare(package: Path, notes: Path | None, mirror_prefix: str | None) -> list[Path]:
    version = (ROOT / "VERSION").read_text().strip()
    if package.name != f"PaimonToolbox-{version}.dmg" or not package.is_file():
        raise ValueError("The DMG filename must match VERSION")
    sdk = ensure_sparkle()
    github_prefix = public_url(f"https://github.com/{REPOSITORY}/releases/download/v{version}")
    feeds = [("appcast.xml", github_prefix)]
    if mirror_prefix:
        feeds.append(("appcast-jianguoyun.xml", public_url(mirror_prefix)))
    output = ROOT / "dist" / "software-update"
    output.mkdir(parents=True, exist_ok=True)
    if not mirror_prefix:
        (output / "appcast-jianguoyun.xml").unlink(missing_ok=True)
    key = os.environ.get("SPARKLE_ED25519_PRIVATE_KEY")
    results = []
    for filename, prefix in feeds:
        with tempfile.TemporaryDirectory(prefix="paimon-appcast-") as temporary:
            archives = Path(temporary)
            shutil.copy2(package, archives / package.name)
            if notes:
                shutil.copy2(notes, archives / (package.stem + ".md"))
            generated = archives / filename
            command = [str(sdk / "bin/generate_appcast"), "--maximum-deltas", "0",
                       "--download-url-prefix", prefix, "--embed-release-notes",
                       "--link", f"https://github.com/{REPOSITORY}/releases/latest", "-o", str(generated)]
            command += ["--ed-key-file", "-"] if key else ["--account", KEY_ACCOUNT]
            command.append(str(archives))
            subprocess.run(command, input=key.encode() if key else None, check=True)
            validate_feed(generated, package, version, prefix)
            target = output / filename
            shutil.copy2(generated, target)
            results.append(target)
    manifest = {
        "version": version,
        "tag": f"v{version}",
        "filename": package.name,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "size": package.stat().st_size,
        "githubURL": github_prefix + urllib.parse.quote(package.name),
        "automaticMirrorAvailable": bool(mirror_prefix),
    }
    manifest_path = output / "software-latest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    results.append(manifest_path)
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path)
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--mirror-download-base-url", default=os.environ.get("SOFTWARE_MIRROR_DOWNLOAD_BASE_URL"))
    args = parser.parse_args()
    version = (ROOT / "VERSION").read_text().strip()
    package = args.package or ROOT / "dist" / f"PaimonToolbox-{version}.dmg"
    for path in prepare(package.resolve(), args.notes, args.mirror_download_base_url):
        print(path)


if __name__ == "__main__":
    main()
