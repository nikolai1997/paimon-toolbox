#!/usr/bin/env python3
"""Fetch the pinned Sparkle distribution used by Xcode and release tools."""

import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.10.1"
SHA256 = "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SDK_DIRECTORY = ROOT / ".cache" / "sparkle-updater" / VERSION
URL = f"https://github.com/sparkle-project/Sparkle/releases/download/{VERSION}/Sparkle-{VERSION}.tar.xz"


def ensure_sparkle() -> Path:
    marker = SDK_DIRECTORY / ".verified-sha256"
    if marker.is_file() and marker.read_text().strip() == SHA256:
        if (SDK_DIRECTORY / "Sparkle.framework").is_dir() and (SDK_DIRECTORY / "bin/generate_appcast").is_file():
            return SDK_DIRECTORY
    SDK_DIRECTORY.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=SDK_DIRECTORY.parent) as temporary:
        staging = Path(temporary)
        archive = staging / "Sparkle.tar.xz"
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2",
                        "--connect-timeout", "15", "--max-time", "180", URL, "--output", str(archive)], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
            raise RuntimeError("Sparkle archive checksum mismatch")
        unpacked = staging / "sdk"
        unpacked.mkdir()
        with tarfile.open(archive) as source:
            if hasattr(tarfile, "data_filter"):
                source.extractall(unpacked, filter="data")
            else:
                # Older macOS Python lacks extraction filters; the archive is pinned above.
                subprocess.run(["/usr/bin/tar", "-xf", str(archive), "-C", str(unpacked)], check=True)
        if not (unpacked / "Sparkle.framework").is_dir():
            raise RuntimeError("Sparkle framework is missing")
        if SDK_DIRECTORY.exists():
            raise RuntimeError(f"Incomplete Sparkle cache: {SDK_DIRECTORY}")
        (unpacked / ".verified-sha256").write_text(SHA256 + "\n")
        shutil.move(str(unpacked), str(SDK_DIRECTORY))
    return SDK_DIRECTORY


if __name__ == "__main__":
    print(ensure_sparkle())
