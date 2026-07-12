#!/usr/bin/env python3
"""Generate public remote-data JSON and an offline data-pack zip."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SNAP_METADATA_REPO_URL = "https://github.com/SnapHutaoRemasteringProject/Snap.Metadata.git"
GENSHIN_DB_REPO_URL = "https://github.com/theBowja/genshin-db.git"
ASSET_BASE_URL = "https://enka.network/ui"
OFFICIAL_ANNOUNCEMENTS_URL = "https://hk4e-ann-api.mihoyo.com/common/hk4e_cn/announcement/api/getAnnList?game=hk4e&game_biz=hk4e_cn&lang=zh-cn&bundle_id=hk4e_cn&platform=pc&region=cn_gf01&level=55&uid=100000000"
MANAGED_CACHE_MARKER = ".paimon-toolbox-managed-cache"
GENSHIN_DB_SPARSE_PATHS = [
    "src/data/ChineseSimplified/characters",
    "src/data/ChineseSimplified/talents",
    "src/data/ChineseSimplified/weapons",
    "src/data/ChineseSimplified/materials",
    "src/data/image",
]
WEAPON_TYPES = {
    1: "单手剑",
    10: "双手剑",
    11: "弓",
    12: "法器",
    13: "长柄武器",
}
ASSOCIATIONS = {
    1: "蒙德",
    2: "璃月",
    3: "稻妻",
    4: "须弥",
    5: "稻妻",
    6: "枫丹",
    7: "纳塔",
    8: "至冬",
}
STAT_TYPES = {
    1: "生命值",
    4: "攻击力",
    7: "防御力",
    20: "暴击率",
    22: "暴击伤害",
    23: "元素充能效率",
    26: "元素精通",
    28: "治疗加成",
}


@dataclass(frozen=True)
class GeneratedFile:
    path: str
    kind: str


PUBLIC_DATA_FILE_SPECS = (
    GeneratedFile("metadata.json", "metadata"),
    GeneratedFile("characters.json", "characters"),
    GeneratedFile("weapons.json", "weapons"),
    GeneratedFile("materials.json", "materials"),
    GeneratedFile("gacha-events.json", "gachaEvents"),
    GeneratedFile("config.json", "config"),
    GeneratedFile("latest.json", "latest"),
    GeneratedFile("announcements.json", "announcements"),
    GeneratedFile("manifest.json", "manifest"),
)


@dataclass(frozen=True)
class RemoteDataPayload:
    source: str
    version_prefix: str
    characters: list[dict[str, Any]]
    weapons: list[dict[str, Any]]
    materials: list[dict[str, Any]]
    gacha_events: list[dict[str, Any]]
    announcements: dict[str, Any] | None = None


def main() -> int:
    parser = argparse.ArgumentParser(description="Update PaimonToolbox remote data artifacts.")
    parser.add_argument(
        "--source",
        choices=["snap-metadata", "official-manual", "genshin-db"],
        default="genshin-db",
        help="data source provider, default: genshin-db",
    )
    parser.add_argument("--locale", default="CHS", help="Snap.Metadata locale folder, default: CHS")
    parser.add_argument("--source-cache", default=".cache/Snap.Metadata", help="local Snap.Metadata checkout")
    parser.add_argument("--genshin-db-cache", default=".cache/genshin-db", help="local genshin-db checkout")
    parser.add_argument("--manual-dir", default="data/manual", help="manual patch directory for official-manual source")
    parser.add_argument(
        "--gacha-source",
        choices=["manual", "snap-metadata"],
        default="snap-metadata",
        help="gacha event source for genshin-db/official-manual mode, default: snap-metadata",
    )
    parser.add_argument(
        "--official-announcements-json",
        default="",
        help="optional local official announcement JSON to merge into announcements.json",
    )
    parser.add_argument(
        "--fetch-official-announcements",
        action="store_true",
        help="fetch official announcement list from miHoYo and cache it under manual-dir",
    )
    parser.add_argument("--public-dir", default="data/public", help="output directory for GitHub Pages JSON")
    parser.add_argument("--release-dir", default="data/releases", help="output directory for data-pack zip")
    parser.add_argument("--base-url", default="", help="optional public base URL written into config files")
    parser.add_argument("--skip-fetch", action="store_true", help="use existing source-cache without git fetch")
    parser.add_argument("--push", action="store_true", help="commit and push generated files")
    parser.add_argument("--commit-message", default="chore: update remote data", help="git commit message for --push")
    parser.add_argument("--self-test", action="store_true", help="run converter self tests")
    parser.add_argument("--validate-public-dir", default="", help="validate an existing public data directory and exit")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        print("self-test passed")
        return 0

    if args.validate_public_dir:
        public_dir = resolve_repository_path(args.validate_public_dir)
        validate_existing_public_data(public_dir)
        print(f"public data validation passed: {public_dir}")
        return 0

    root = repository_root()
    source_cache = resolve_repository_path(args.source_cache, root)
    genshin_db_cache = resolve_repository_path(args.genshin_db_cache, root)
    manual_dir = resolve_repository_path(args.manual_dir, root)
    public_dir = resolve_repository_path(args.public_dir, root)
    release_dir = resolve_repository_path(args.release_dir, root)
    official_announcements_json = (
        resolve_repository_path(args.official_announcements_json, root)
        if args.official_announcements_json
        else None
    )

    if args.source == "snap-metadata":
        ensure_source_checkout(source_cache, skip_fetch=args.skip_fetch)
        locale_dir = source_cache / "Genshin" / args.locale
        if not locale_dir.exists():
            raise SystemExit(f"Missing locale directory: {locale_dir}")
        payload = build_snap_metadata_payload(locale_dir)
    elif args.source == "official-manual":
        gacha_events_override = None
        manual_gacha_events = read_json_if_exists(manual_dir / "gacha-events.json") or []
        if args.gacha_source == "snap-metadata":
            try:
                snap_gacha_events = load_snap_gacha_events(source_cache, args.locale, args.skip_fetch)
                gacha_events_override = select_fresher_gacha_events(
                    snap_gacha_events,
                    manual_gacha_events,
                    primary_label="Snap.Metadata",
                    fallback_label="manual gacha-events.json",
                )
            except Exception as error:
                gacha_events_override = current_or_manual_gacha_events(public_dir, manual_gacha_events)
                print(f"warning: Snap.Metadata gacha fetch failed, preserving freshest local gacha data: {error}", file=sys.stderr)
        payload = build_official_manual_payload(
            manual_dir,
            official_announcements_json=official_announcements_json,
            fetch_official_announcements=args.fetch_official_announcements,
            gacha_events_override=gacha_events_override,
            current_public_announcements=public_dir / "announcements.json",
        )
    else:
        announcements = load_announcements(
            manual_dir,
            official_announcements_json=official_announcements_json,
            fetch_official_announcements=args.fetch_official_announcements,
            current_public_announcements=public_dir / "announcements.json",
        )
        gacha_events = read_json(manual_dir / "gacha-events.json")
        if args.gacha_source == "snap-metadata":
            try:
                snap_gacha_events = load_snap_gacha_events(source_cache, args.locale, args.skip_fetch)
                gacha_events = select_fresher_gacha_events(
                    snap_gacha_events,
                    gacha_events,
                    primary_label="Snap.Metadata",
                    fallback_label="manual gacha-events.json",
                )
            except Exception as error:
                gacha_events = current_or_manual_gacha_events(public_dir, gacha_events)
                print(f"warning: Snap.Metadata gacha fetch failed, preserving freshest local gacha data: {error}", file=sys.stderr)
        ensure_genshin_db_checkout(genshin_db_cache, skip_fetch=args.skip_fetch)
        payload = build_genshin_db_payload(genshin_db_cache, gacha_events=gacha_events, announcements=announcements)

    payload = replace(
        payload,
        gacha_events=merge_official_gacha_events(
            payload.gacha_events,
            payload.announcements,
            characters=payload.characters,
            weapons=payload.weapons,
        ),
    )

    generated = generate_public_data(payload, public_dir, args.base_url)
    zip_path = package_release(public_dir, release_dir, generated)
    print(f"wrote {public_dir}")
    print(f"wrote {zip_path}")

    if args.push:
        commit_and_push([public_dir], args.commit_message, repository=root)

    return 0


def repository_root() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_repository_path(value: str | Path, root: Path | None = None) -> Path:
    path = Path(value).expanduser()
    if path.is_absolute():
        return path.resolve()
    return ((root or repository_root()) / path).resolve()


def ensure_source_checkout(source_cache: Path, skip_fetch: bool) -> None:
    ensure_git_checkout(SNAP_METADATA_REPO_URL, source_cache, skip_fetch=skip_fetch)


def ensure_genshin_db_checkout(source_cache: Path, skip_fetch: bool) -> None:
    ensure_git_checkout(GENSHIN_DB_REPO_URL, source_cache, skip_fetch=skip_fetch, sparse_paths=GENSHIN_DB_SPARSE_PATHS)


def ensure_git_checkout(
    repo_url: str,
    source_cache: Path,
    skip_fetch: bool,
    sparse_paths: list[str] | None = None,
    workspace: Path | None = None,
) -> None:
    workspace = (workspace or repository_root()).resolve()
    source_cache = source_cache.expanduser().resolve()
    validate_cache_location(source_cache, workspace)

    if skip_fetch:
        if not source_cache.exists():
            raise SystemExit(f"{source_cache} does not exist; rerun without --skip-fetch")
        validate_managed_cache_path(source_cache, workspace, repo_url)
        return

    source_cache.parent.mkdir(parents=True, exist_ok=True)
    if (source_cache / ".git").exists():
        if not (source_cache / MANAGED_CACHE_MARKER).is_file():
            raise RuntimeError(f"refusing to manage unmarked existing checkout: {source_cache}")
        validate_managed_cache_path(source_cache, workspace, repo_url)
        run(["git", "-C", str(source_cache), "fetch", "--depth", "1", "origin", "main"])
        run(["git", "-C", str(source_cache), "reset", "--hard", "origin/main"])
        if sparse_paths:
            run(["git", "-C", str(source_cache), "sparse-checkout", "set", *sparse_paths])
        return

    if sparse_paths:
        run(["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse", repo_url, str(source_cache)])
        run(["git", "-C", str(source_cache), "sparse-checkout", "set", *sparse_paths])
    else:
        run(["git", "clone", "--depth", "1", repo_url, str(source_cache)])
    write_managed_cache_marker(source_cache)


def validate_cache_location(source_cache: Path, workspace: Path) -> None:
    resolved = source_cache.expanduser().resolve()
    workspace = workspace.expanduser().resolve()
    managed_root = workspace / ".cache"
    if resolved in {workspace, Path.home().resolve(), Path("/")}:
        raise RuntimeError(f"refusing destructive git operation at unsafe path: {resolved}")
    try:
        resolved.relative_to(managed_root)
    except ValueError as error:
        raise RuntimeError(f"cache must be inside {managed_root}: {resolved}") from error


def validate_managed_cache_path(source_cache: Path, workspace: Path, expected_repo_url: str) -> Path:
    resolved = source_cache.expanduser().resolve()
    validate_cache_location(resolved, workspace)
    marker = resolved / MANAGED_CACHE_MARKER
    if not marker.is_file() or marker.read_text(encoding="utf-8").strip() != "managed":
        raise RuntimeError(f"refusing destructive git operation outside managed cache: {resolved}")
    try:
        origin = subprocess.run(
            ["git", "-C", str(resolved), "remote", "get-url", "origin"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"refusing destructive git operation without a readable origin: {resolved}") from error
    if normalize_git_remote(origin) != normalize_git_remote(expected_repo_url):
        raise RuntimeError(
            f"refusing destructive git operation for mismatched origin: {origin} (expected {expected_repo_url})"
        )
    return resolved


def write_managed_cache_marker(source_cache: Path) -> None:
    (source_cache / MANAGED_CACHE_MARKER).write_text("managed\n", encoding="utf-8")


def normalize_git_remote(value: str) -> str:
    return value.strip().rstrip("/").removesuffix(".git").rstrip("/").lower()


def build_snap_metadata_payload(locale_dir: Path) -> RemoteDataPayload:
    materials_raw = read_json(locale_dir / "Material.json")
    material_names = {item["Id"]: item.get("Name", str(item["Id"])) for item in materials_raw}

    return RemoteDataPayload(
        source="snap-metadata",
        version_prefix="snap",
        characters=convert_characters(locale_dir / "Avatar", material_names),
        weapons=convert_weapons(read_json(locale_dir / "Weapon.json"), material_names),
        materials=convert_materials(materials_raw),
        gacha_events=convert_gacha_events(read_json(locale_dir / "GachaEvent.json")),
    )


def build_genshin_db_payload(
    source_cache: Path,
    gacha_events: list[dict[str, Any]],
    announcements: dict[str, Any] | None,
) -> RemoteDataPayload:
    locale_dir = source_cache / "src" / "data" / "ChineseSimplified"
    image_dir = source_cache / "src" / "data" / "image"
    if not locale_dir.exists():
        raise SystemExit(f"Missing genshin-db locale directory: {locale_dir}")

    character_images = read_json_if_exists(image_dir / "characters.json") or {}
    weapon_images = read_json_if_exists(image_dir / "weapons.json") or {}
    material_images = read_json_if_exists(image_dir / "materials.json") or {}

    return RemoteDataPayload(
        source="genshin-db",
        version_prefix="genshin-db",
        characters=convert_genshin_db_characters(locale_dir / "characters", locale_dir / "talents", character_images),
        weapons=convert_genshin_db_weapons(locale_dir / "weapons", weapon_images),
        materials=convert_genshin_db_materials(locale_dir / "materials", material_images),
        gacha_events=gacha_events,
        announcements=announcements,
    )


def load_snap_gacha_events(source_cache: Path, locale: str, skip_fetch: bool) -> list[dict[str, Any]]:
    ensure_source_checkout(source_cache, skip_fetch=skip_fetch)
    locale_dir = source_cache / "Genshin" / locale
    if not locale_dir.exists():
        raise FileNotFoundError(f"Missing locale directory: {locale_dir}")
    return convert_gacha_events(read_json(locale_dir / "GachaEvent.json"))


def select_fresher_gacha_events(
    primary: list[dict[str, Any]],
    fallback: list[dict[str, Any]],
    primary_label: str,
    fallback_label: str,
) -> list[dict[str, Any]]:
    if not fallback:
        return primary
    primary_key = gacha_freshness_key(primary)
    fallback_key = gacha_freshness_key(fallback)
    if fallback_key > primary_key:
        print(
            f"warning: {primary_label} gacha data looks older than {fallback_label}; using fallback",
            file=sys.stderr,
        )
        return fallback
    return primary


def gacha_freshness_key(events: list[dict[str, Any]]) -> tuple[datetime, int]:
    latest = max(
        (parse_gacha_datetime(event.get("to") or event.get("To")) for event in events),
        default=datetime.min.replace(tzinfo=timezone.utc),
    )
    return latest, len(events)


def parse_gacha_datetime(value: Any) -> datetime:
    if not isinstance(value, str) or not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.min.replace(tzinfo=timezone.utc)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def load_announcements(
    manual_dir: Path,
    official_announcements_json: Path | None,
    fetch_official_announcements: bool,
    current_public_announcements: Path | None = None,
) -> dict[str, Any]:
    manual = read_json_if_exists(manual_dir / "announcements.json") or empty_announcements()
    current = read_json_if_exists(current_public_announcements) if current_public_announcements else None
    official_json_path = official_announcements_json
    if fetch_official_announcements:
        official_json_path = fetch_official_announcements_json_if_available(manual_dir)
    if official_json_path is not None:
        official = convert_official_announcements(read_json(official_json_path))
        return select_announcement_feed(official, current, manual)
    selected = select_announcement_feed(current, manual)
    if fetch_official_announcements and not selected.get("items"):
        raise RuntimeError("official announcement fetch failed and no nonempty fallback feed is available")
    return selected


def select_announcement_feed(*feeds: dict[str, Any] | None) -> dict[str, Any]:
    valid = [feed for feed in feeds if isinstance(feed, dict) and isinstance(feed.get("items"), list)]
    if not valid:
        raise RuntimeError("no valid announcement feed is available")
    nonempty = [feed for feed in valid if feed.get("items")]
    candidates = nonempty or valid
    return max(candidates, key=lambda feed: parse_gacha_datetime(feed.get("updatedAt")))


def current_or_manual_gacha_events(public_dir: Path, manual_events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    current = read_json_if_exists(public_dir / "gacha-events.json") or []
    if not current:
        return manual_events
    if not manual_events:
        return current
    return select_fresher_gacha_events(
        current,
        manual_events,
        primary_label="current public gacha-events.json",
        fallback_label="manual gacha-events.json",
    )


def build_official_manual_payload(
    manual_dir: Path,
    official_announcements_json: Path | None,
    fetch_official_announcements: bool,
    gacha_events_override: list[dict[str, Any]] | None = None,
    current_public_announcements: Path | None = None,
) -> RemoteDataPayload:
    required = [
        "characters.json",
        "weapons.json",
        "materials.json",
        "gacha-events.json",
    ]
    missing = [name for name in required if not (manual_dir / name).exists()]
    if missing:
        raise SystemExit(f"Missing manual patch files in {manual_dir}: {', '.join(missing)}")

    announcements = load_announcements(
        manual_dir,
        official_announcements_json=official_announcements_json,
        fetch_official_announcements=fetch_official_announcements,
        current_public_announcements=current_public_announcements,
    )

    payload = RemoteDataPayload(
        source="official-manual",
        version_prefix="manual",
        characters=read_json(manual_dir / "characters.json"),
        weapons=read_json(manual_dir / "weapons.json"),
        materials=read_json(manual_dir / "materials.json"),
        gacha_events=gacha_events_override if gacha_events_override is not None else read_json(manual_dir / "gacha-events.json"),
        announcements=announcements,
    )
    asset_overrides = read_json_if_exists(manual_dir / "assets.json")
    if asset_overrides:
        apply_asset_overrides(payload, asset_overrides)
    return payload


def generate_public_data(payload: RemoteDataPayload, public_dir: Path, base_url: str) -> list[GeneratedFile]:
    public_dir = public_dir.expanduser().resolve()
    public_dir.parent.mkdir(parents=True, exist_ok=True)
    staging_dir = Path(tempfile.mkdtemp(prefix=f".{public_dir.name}.staging-", dir=public_dir.parent))
    try:
        generated = write_public_data(payload, staging_dir, public_dir, base_url)
        validate_public_data(staging_dir, generated)
        replace_directory_atomically(staging_dir, public_dir)
        return generated
    finally:
        if staging_dir.exists():
            shutil.rmtree(staging_dir)


def write_public_data(
    payload: RemoteDataPayload,
    output_dir: Path,
    previous_public_dir: Path,
    base_url: str,
) -> list[GeneratedFile]:
    now = datetime.now(timezone.utc)
    announcements = normalize_announcement_feed(payload.announcements or empty_announcements())
    previous_metadata = read_json_if_exists(previous_public_dir / "metadata.json") or {}
    apply_asset_overrides(payload, previous_metadata)
    previous_announcements = read_json_if_exists(previous_public_dir / "announcements.json") or {}
    previous_gacha_events = read_json_if_exists(previous_public_dir / "gacha-events.json") or []
    data_changed = (
        previous_metadata.get("characters") != payload.characters
        or previous_metadata.get("weapons") != payload.weapons
        or previous_metadata.get("materials") != payload.materials
        or previous_gacha_events != payload.gacha_events
        or previous_announcements.get("items") != announcements.get("items")
    )
    previous_version = previous_metadata.get("version")
    previous_updated_at = previous_metadata.get("updatedAt")
    if not data_changed and isinstance(previous_version, str) and isinstance(previous_updated_at, str):
        version = previous_version
        updated_at = previous_updated_at
    else:
        version = f"{payload.version_prefix}-{now.strftime('%Y.%m.%d')}"
        updated_at = isoformat_z(now)

    metadata = {
        "version": version,
        "updatedAt": updated_at,
        "characters": payload.characters,
        "weapons": payload.weapons,
        "materials": payload.materials,
    }
    config = {
        "schemaVersion": 1,
        "baseURL": base_url.rstrip("/"),
        "preferredUpdateChannel": "github-pages",
        "dataSource": payload.source,
        "offlinePackageName": f"data-pack-{now.strftime('%Y.%m.%d')}.zip",
    }
    latest = {
        "schemaVersion": 1,
        "dataVersion": metadata["version"],
        "updatedAt": metadata["updatedAt"],
        "required": False,
        "notes": "资料库数据更新",
    }
    announcements["updatedAt"] = metadata["updatedAt"]

    files = [
        ("metadata.json", "metadata", metadata),
        ("characters.json", "characters", payload.characters),
        ("weapons.json", "weapons", payload.weapons),
        ("materials.json", "materials", payload.materials),
        ("gacha-events.json", "gachaEvents", payload.gacha_events),
        ("config.json", "config", config),
        ("latest.json", "latest", latest),
        ("announcements.json", "announcements", announcements),
    ]

    generated: list[GeneratedFile] = []
    for file_name, kind, file_payload in files:
        write_json(output_dir / file_name, file_payload)
        generated.append(GeneratedFile(file_name, kind))

    manifest = {
        "schemaVersion": 1,
        "generatedAt": metadata["updatedAt"],
        "files": [
            {
                "path": item.path,
                "sha256": sha256_file(output_dir / item.path),
                "kind": item.kind,
            }
            for item in generated
        ],
    }
    write_json(output_dir / "manifest.json", manifest)
    generated.append(GeneratedFile("manifest.json", "manifest"))
    return generated


def validate_public_data(public_dir: Path, generated: list[GeneratedFile]) -> None:
    expected = {item.path: item.kind for item in generated}
    if expected.get("manifest.json") != "manifest" or len(expected) != len(generated):
        raise RuntimeError("generated public data file list is invalid")

    actual = {path.name for path in public_dir.iterdir() if path.is_file()}
    if actual != set(expected) or any(not path.is_file() for path in public_dir.iterdir()):
        raise RuntimeError(f"public data staging members mismatch: expected {sorted(expected)}, got {sorted(actual)}")

    for path in expected:
        read_json(public_dir / path)

    validate_announcement_feed(read_json(public_dir / "announcements.json"))

    manifest = read_json(public_dir / "manifest.json")
    records = manifest.get("files")
    if not isinstance(records, list):
        raise RuntimeError("public data manifest files must be a list")
    expected_payloads = {path: kind for path, kind in expected.items() if path != "manifest.json"}
    if len(records) != len(expected_payloads):
        raise RuntimeError("public data manifest member count mismatch")

    seen: set[str] = set()
    for record in records:
        if not isinstance(record, dict):
            raise RuntimeError("public data manifest contains an invalid record")
        path = record.get("path")
        if path in seen or path not in expected_payloads:
            raise RuntimeError(f"public data manifest contains an unexpected path: {path}")
        seen.add(path)
        if record.get("kind") != expected_payloads[path]:
            raise RuntimeError(f"public data manifest kind mismatch: {path}")
        if record.get("sha256") != sha256_file(public_dir / path):
            raise RuntimeError(f"public data manifest hash mismatch: {path}")
    if seen != set(expected_payloads):
        raise RuntimeError("public data manifest is incomplete")


def validate_existing_public_data(public_dir: Path) -> None:
    public_dir = public_dir.expanduser().resolve()
    if not public_dir.is_dir():
        raise RuntimeError(f"public data directory is missing: {public_dir}")
    validate_public_data(public_dir, list(PUBLIC_DATA_FILE_SPECS))


def replace_directory_atomically(staging_dir: Path, target_dir: Path) -> None:
    if not target_dir.exists():
        os.replace(staging_dir, target_dir)
        return
    if not target_dir.is_dir():
        raise RuntimeError(f"public data target is not a directory: {target_dir}")

    backup_dir = Path(tempfile.mkdtemp(prefix=f".{target_dir.name}.backup-", dir=target_dir.parent))
    backup_dir.rmdir()
    os.replace(target_dir, backup_dir)
    try:
        os.replace(staging_dir, target_dir)
    except Exception:
        try:
            os.replace(backup_dir, target_dir)
        except Exception as restore_error:
            raise RuntimeError(
                f"failed to publish public data and restore previous directory; backup remains at {backup_dir}"
            ) from restore_error
        raise
    else:
        shutil.rmtree(backup_dir, ignore_errors=True)


def apply_asset_overrides(payload: RemoteDataPayload, asset_payload: dict[str, Any]) -> None:
    merge_asset_fields(payload.characters, asset_payload.get("characters"), ["iconURL", "portraitURL"])
    merge_asset_fields(payload.weapons, asset_payload.get("weapons"), ["iconURL"])
    merge_asset_fields(payload.materials, asset_payload.get("materials"), ["iconURL"])


def merge_asset_fields(items: list[dict[str, Any]], asset_items: Any, fields: list[str]) -> None:
    if not isinstance(asset_items, list):
        return

    by_id: dict[Any, dict[str, Any]] = {}
    by_name: dict[str, dict[str, Any]] = {}
    for asset_item in asset_items:
        if not isinstance(asset_item, dict):
            continue
        item_id = asset_item.get("id")
        if item_id is not None:
            by_id[item_id] = asset_item
        name = asset_item.get("name")
        if isinstance(name, str) and name:
            by_name[name] = asset_item

    for item in items:
        asset_item = by_id.get(item.get("id"))
        if asset_item is None:
            name = item.get("name")
            asset_item = by_name.get(name) if isinstance(name, str) else None
        if asset_item is None:
            continue
        for field in fields:
            if item.get(field):
                continue
            value = asset_item.get(field)
            if isinstance(value, str) and value:
                item[field] = value


def convert_genshin_db_characters(character_dir: Path, talent_dir: Path, image_index: dict[str, Any]) -> list[dict[str, Any]]:
    characters: list[dict[str, Any]] = []
    for path in sorted(character_dir.glob("*.json")):
        character = read_json(path)
        talent = read_json_if_exists(talent_dir / path.name) or {}
        name = character.get("name")
        if not name:
            continue

        item = {
            "id": character["id"],
            "name": name,
            "element": character.get("elementText") or "无",
            "weaponType": character.get("weaponText") or "未知",
            "rarity": character.get("rarity", 0),
            "region": character.get("region") or character.get("affiliation") or "未知",
            "materials": merge_unique_names(
                collect_cost_names(character.get("costs")),
                collect_cost_names(talent.get("costs")),
            ),
        }
        cultivation = infer_genshin_db_character_cultivation(character.get("costs"), talent.get("costs"))
        if cultivation:
            item["cultivation"] = cultivation
        image_payload = image_index.get(path.stem) if isinstance(image_index, dict) else None
        if isinstance(image_payload, dict):
            add_asset_url(item, "iconURL", first_string(image_payload, "filename_icon"))
            add_asset_url(item, "portraitURL", first_string(image_payload, "filename_sideIcon", "filename_iconCard"))
        characters.append(item)
    return sorted(characters, key=lambda item: (item["rarity"], item["id"]), reverse=True)


def convert_genshin_db_weapons(weapon_dir: Path, image_index: dict[str, Any]) -> list[dict[str, Any]]:
    weapons: list[dict[str, Any]] = []
    for path in sorted(weapon_dir.glob("*.json")):
        weapon = read_json(path)
        name = weapon.get("name")
        if not name:
            continue

        item = {
            "id": weapon["id"],
            "name": name,
            "type": weapon.get("weaponText") or "未知",
            "rarity": weapon.get("rarity", 0),
            "stat": weapon.get("mainStatText") or "基础攻击力",
            "materials": collect_cost_names(weapon.get("costs")),
        }
        ascension_stages = convert_weapon_ascension_stages(weapon.get("costs"))
        if ascension_stages:
            item["ascensionStages"] = ascension_stages
        image_payload = image_index.get(path.stem) if isinstance(image_index, dict) else None
        if isinstance(image_payload, dict):
            add_asset_url(item, "iconURL", first_string(image_payload, "filename_icon"))
        weapons.append(item)
    return sorted(weapons, key=lambda item: (item["rarity"], item["id"]), reverse=True)


def convert_weapon_ascension_stages(costs: Any) -> list[dict[str, Any]]:
    if not isinstance(costs, dict):
        return []
    breakpoints = [20, 40, 50, 60, 70, 80]
    stages: list[dict[str, Any]] = []
    for index, breakpoint in enumerate(breakpoints, start=1):
        entries = costs.get(f"ascend{index}")
        if not isinstance(entries, list) or not entries:
            return []
        converted_costs: list[dict[str, Any]] = []
        for entry in entries:
            if not isinstance(entry, dict):
                return []
            name = entry.get("name")
            count = entry.get("count")
            if not isinstance(name, str) or not name or not isinstance(count, int) or count <= 0:
                return []
            converted_costs.append({"materialName": name, "count": count})
        stages.append({"breakpoint": breakpoint, "costs": converted_costs})
    return stages


def convert_genshin_db_materials(material_dir: Path, image_index: dict[str, Any]) -> list[dict[str, Any]]:
    materials: list[dict[str, Any]] = []
    for path in sorted(material_dir.glob("*.json")):
        material = read_json(path)
        name = material.get("name")
        if not name:
            continue

        sources = material.get("sources") or []
        item = {
            "id": material["id"],
            "name": name,
            "category": material.get("typeText") or material.get("category") or "材料",
            "source": "\n".join(sources) if sources else material.get("description", ""),
        }
        image_payload = image_index.get(path.stem) if isinstance(image_index, dict) else None
        if isinstance(image_payload, dict):
            add_asset_url(item, "iconURL", first_string(image_payload, "filename_icon"))
        if not item.get("iconURL"):
            add_asset_url(item, "iconURL", f"UI_ItemIcon_{item['id']}")
        materials.append(item)
    return sorted(materials, key=lambda item: item["id"])


def collect_cost_names(costs: Any) -> list[str]:
    if not isinstance(costs, dict):
        return []
    names: list[str] = []
    for key in sorted(costs):
        entries = costs.get(key)
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if not isinstance(name, str) or not name or name == "摩拉":
                continue
            if name not in names:
                names.append(name)
    return names


def merge_unique_names(*groups: list[str]) -> list[str]:
    names: list[str] = []
    for group in groups:
        for name in group:
            if name not in names:
                names.append(name)
    return names


def infer_genshin_db_character_cultivation(ascension_costs: Any, talent_costs: Any = None) -> dict[str, Any] | None:
    if not isinstance(ascension_costs, dict):
        return None
    ascend_entries: list[dict[str, Any]] = []
    talent_entries: list[dict[str, Any]] = []
    for key, entries in ascension_costs.items():
        if not isinstance(entries, list):
            continue
        if str(key).startswith("ascend"):
            ascend_entries.extend(entry for entry in entries if isinstance(entry, dict))
    if isinstance(talent_costs, dict):
        for key, entries in talent_costs.items():
            if isinstance(entries, list) and str(key).startswith("lvl"):
                talent_entries.extend(entry for entry in entries if isinstance(entry, dict))

    gems = names_by_id_range(ascend_entries, 104100, 104199)
    boss = first_matching_entry_name(ascend_entries, exclude=set(gems), min_id=113000, max_id=113999)
    local = first_matching_entry_name(ascend_entries, exclude=set(gems + ([boss] if boss else [])), min_id=100000, max_id=101999)
    common_names = names_by_id_range(ascend_entries, 112000, 112999)
    talent_book_names = names_by_id_range(talent_entries, 104300, 104999, name_filter=is_talent_book_name)
    weekly = first_matching_entry_name(talent_entries, exclude=set(talent_book_names), min_id=113000, max_id=113999)
    cultivation = {
        "ascensionGemNames": gems[:4],
        "bossMaterialName": boss or "",
        "localSpecialtyName": local or "",
        "commonMaterialNames": common_names[:3],
        "talentBookNames": talent_book_names[:3],
        "weeklyBossMaterialName": weekly or "",
    }
    if any(cultivation.values()):
        return cultivation
    return None


def collect_names_from_entries(entries: list[dict[str, Any]]) -> list[str]:
    names: list[str] = []
    for entry in entries:
        name = entry.get("name")
        if isinstance(name, str) and name and name != "摩拉" and name not in names:
            names.append(name)
    return names


def names_by_id_range(
    entries: list[dict[str, Any]],
    min_id: int,
    max_id: int,
    name_filter: Any | None = None,
) -> list[str]:
    names: list[str] = []
    for entry in sorted(entries, key=lambda value: value.get("id", 0)):
        item_id = entry.get("id")
        name = entry.get("name")
        if not isinstance(item_id, int) or not isinstance(name, str):
            continue
        if name_filter is not None and not name_filter(name):
            continue
        if min_id <= item_id <= max_id and name not in names:
            names.append(name)
    return names


def is_talent_book_name(name: str) -> bool:
    return "「" in name and "」" in name


def first_matching_entry_name(entries: list[dict[str, Any]], exclude: set[str], min_id: int, max_id: int) -> str:
    for entry in sorted(entries, key=lambda value: value.get("id", 0)):
        item_id = entry.get("id")
        name = entry.get("name")
        if not isinstance(item_id, int) or not isinstance(name, str) or name in exclude:
            continue
        if min_id <= item_id <= max_id:
            return name
    return ""


def convert_characters(avatar_dir: Path, material_names: dict[int, str]) -> list[dict[str, Any]]:
    characters: list[dict[str, Any]] = []
    for avatar_file in sorted(avatar_dir.glob("*.json")):
        avatar = read_json(avatar_file)
        if not avatar.get("Name"):
            continue

        fetter = avatar.get("FetterInfo") or {}
        item = {
            "id": avatar["Id"],
            "name": avatar["Name"],
            "element": fetter.get("VisionBefore") or "无",
            "weaponType": WEAPON_TYPES.get(avatar.get("Weapon"), "未知"),
            "rarity": avatar.get("Quality", 0),
            "region": ASSOCIATIONS.get(fetter.get("Association"), fetter.get("Native") or "未知"),
            "materials": resolve_materials(avatar.get("CultivationItems", []), material_names),
        }
        cultivation = resolve_character_cultivation_materials(avatar.get("CultivationItems", []), material_names)
        if cultivation:
            item["cultivation"] = cultivation
        add_asset_url(item, "iconURL", first_string(avatar, "Icon", "IconName", "AvatarIcon", "SideIconName"))
        add_asset_url(
            item,
            "portraitURL",
            first_string(avatar, "GachaCard", "GachaCardName", "GachaImageName", "Card", "Portrait", "SideIcon", "SideIconName"),
        )
        characters.append(item)
    return sorted(characters, key=lambda item: (item["rarity"], item["id"]), reverse=True)


def convert_weapons(weapons_raw: list[dict[str, Any]], material_names: dict[int, str]) -> list[dict[str, Any]]:
    weapons: list[dict[str, Any]] = []
    for weapon in weapons_raw:
        if not weapon.get("Name"):
            continue
        item = {
            "id": weapon["Id"],
            "name": weapon["Name"],
            "type": WEAPON_TYPES.get(weapon.get("WeaponType"), "未知"),
            "rarity": weapon.get("RankLevel", 0),
            "stat": weapon_stat(weapon),
            "materials": resolve_materials(weapon.get("CultivationItems", []), material_names),
        }
        add_asset_url(item, "iconURL", first_string(weapon, "Icon", "IconName"))
        weapons.append(item)
    return sorted(weapons, key=lambda item: (item["rarity"], item["id"]), reverse=True)


def convert_materials(materials_raw: list[dict[str, Any]]) -> list[dict[str, Any]]:
    materials: list[dict[str, Any]] = []
    for material in materials_raw:
        if not material.get("Name"):
            continue
        item = {
            "id": material["Id"],
            "name": material["Name"],
            "category": material.get("TypeDescription") or material.get("MaterialType", "材料"),
            "source": material.get("Description") or material.get("TypeDescription") or "",
        }
        add_asset_url(item, "iconURL", first_string(material, "Icon", "IconName"))
        materials.append(item)
    return sorted(materials, key=lambda item: item["id"])


def convert_gacha_events(events_raw: list[dict[str, Any]]) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for event in events_raw:
        events.append(
            {
                "name": event.get("Name", ""),
                "version": event.get("Version", ""),
                "type": event.get("Type", 0),
                "from": event.get("From", ""),
                "to": event.get("To", ""),
                "upOrangeList": event.get("UpOrangeList", []),
                "upPurpleList": event.get("UpPurpleList", []),
                "banner": event.get("Banner", ""),
            }
        )
    return events


def convert_official_announcements(payload: dict[str, Any]) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    data = payload.get("data") or {}
    lists = data.get("list") or []
    for group in lists:
        for announcement in group.get("list", []):
            title = announcement.get("title") or announcement.get("subtitle") or ""
            if not title:
                continue
            items.append(
                {
                    "id": str(announcement.get("ann_id") or announcement.get("id") or title),
                    "title": title,
                    "subtitle": announcement.get("subtitle", ""),
                    "type": announcement.get("type_label") or group.get("type_label") or "",
                    "startTime": announcement.get("start_time", ""),
                    "endTime": announcement.get("end_time", ""),
                    "banner": normalize_optional_http_url(announcement.get("banner")),
                    "contentURL": normalize_optional_http_url(announcement.get("content_url")),
                }
            )
    return {
        "schemaVersion": 1,
        "updatedAt": isoformat_z(datetime.now(timezone.utc)),
        "items": items,
    }


def normalize_announcement_feed(feed: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(feed)
    items = feed.get("items")
    if not isinstance(items, list):
        return normalized

    normalized_items: list[Any] = []
    for item in items:
        if not isinstance(item, dict):
            normalized_items.append(item)
            continue
        normalized_item = dict(item)
        for field in ("banner", "contentURL", "url"):
            if field in normalized_item:
                normalized_item[field] = normalize_optional_http_url(normalized_item[field])
        normalized_items.append(normalized_item)

    normalized["items"] = normalized_items
    return normalized


def normalize_optional_http_url(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    if not normalized:
        return None
    parsed = urllib.parse.urlsplit(normalized)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.netloc:
        return None
    return normalized


def validate_announcement_feed(feed: Any) -> None:
    if not isinstance(feed, dict):
        raise RuntimeError("announcement feed must be an object")
    if type(feed.get("schemaVersion")) is not int or feed["schemaVersion"] != 1:
        raise RuntimeError("announcement schemaVersion must be 1")
    updated_at = feed.get("updatedAt")
    timestamp_pattern = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})"
    if not isinstance(updated_at, str) or re.fullmatch(timestamp_pattern, updated_at) is None:
        raise RuntimeError("announcement updatedAt must be an ISO 8601 timestamp")
    if parse_gacha_datetime(updated_at) == datetime.min.replace(tzinfo=timezone.utc):
        raise RuntimeError("announcement updatedAt must be an ISO 8601 timestamp")
    if not isinstance(feed.get("items"), list):
        raise RuntimeError("announcement feed items must be a list")
    for index, item in enumerate(feed["items"]):
        if not isinstance(item, dict):
            raise RuntimeError(f"announcement item is invalid: {index}")

        for field in ("id", "title"):
            value = item.get(field)
            if not isinstance(value, str) or not value.strip():
                raise RuntimeError(f"announcement field is invalid: items[{index}].{field}")

        for field in ("subtitle", "type", "typeLabel", "startTime", "endTime", "startsAt", "endsAt"):
            value = item.get(field)
            if value is not None and not isinstance(value, str):
                raise RuntimeError(f"announcement field is invalid: items[{index}].{field}")

        for field in ("banner", "contentURL", "url"):
            value = item.get(field)
            if value is None:
                continue
            if not isinstance(value, str) or normalize_optional_http_url(value) != value:
                raise RuntimeError(f"announcement url field is invalid: items[{index}].{field}")


def merge_official_gacha_events(
    events: list[dict[str, Any]],
    announcements: dict[str, Any],
    characters: list[dict[str, Any]],
    weapons: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    official_events = official_gacha_events_from_announcements(announcements, characters, weapons)
    if not official_events:
        return events

    merged: dict[tuple[int, str, str], dict[str, Any]] = {}
    order: list[tuple[int, str, str]] = []
    for event in events:
        key = gacha_event_merge_key(event)
        if key not in merged:
            order.append(key)
        merged[key] = event
    for event in official_events:
        key = gacha_event_merge_key(event)
        if key not in merged:
            order.append(key)
            merged[key] = event
        else:
            merged[key] = merge_gacha_event_fields(merged[key], event)
    return [merged[key] for key in order]


def gacha_event_merge_key(event: dict[str, Any]) -> tuple[int, str, str]:
    return (int(event.get("type") or 0), str(event.get("name") or ""), str(event.get("to") or ""))


def merge_gacha_event_fields(existing: dict[str, Any], fallback: dict[str, Any]) -> dict[str, Any]:
    merged = dict(existing)
    list_fields = {"upOrangeList", "upPurpleList"}
    for field, value in fallback.items():
        current = merged.get(field)
        if field in list_fields:
            if (not isinstance(current, list) or not current) and isinstance(value, list):
                merged[field] = value
        elif (current is None or current == "") and value not in (None, ""):
            merged[field] = value
    return merged


def official_gacha_events_from_announcements(
    announcements: dict[str, Any],
    characters: list[dict[str, Any]],
    weapons: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    items = announcements.get("items") if isinstance(announcements, dict) else []
    if not isinstance(items, list):
        return []

    character_ids = id_lookup(characters)
    weapon_ids = id_lookup(weapons)
    version_ranges = official_version_ranges(items)
    candidates: list[dict[str, Any]] = []
    character_candidate_indexes: list[int] = []

    for item in items:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title") or "")
        subtitle = str(item.get("subtitle") or "")
        combined = f"{title} {subtitle}"
        if "祈愿" not in combined:
            continue
        if "常驻祈愿" in combined or "奔行世间" in combined:
            continue

        quoted = re.findall(r"「([^」]+)」", title)
        if not quoted:
            quoted = re.findall(r"「([^」]+)」", subtitle)
        if not quoted:
            continue

        name = quoted[0]
        event_type = official_gacha_type(name, combined)
        if event_type == 0 and "概率UP" not in combined:
            continue

        start = official_time_to_iso(item.get("startsAt") or item.get("startTime"))
        end = official_time_to_iso(item.get("endsAt") or item.get("endTime"))
        if not start or not end:
            continue

        up_names = [clean_gacha_item_name(value) for value in quoted[1:]]
        lookup = weapon_ids if event_type == 302 else character_ids
        if event_type == 500:
            lookup = {**character_ids, **weapon_ids}
        candidate = {
            "name": name,
            "version": official_version_for_event(start, version_ranges),
            "type": event_type,
            "from": start,
            "to": end,
            "upOrangeList": ids_for_names(up_names, lookup),
            "upPurpleList": [],
            "banner": item.get("banner") or "",
        }
        if event_type == 0:
            character_candidate_indexes.append(len(candidates))
        candidates.append(candidate)

    assign_character_gacha_types(candidates, character_candidate_indexes)
    return [event for event in candidates if int(event.get("type") or 0) != 0]


def official_gacha_type(name: str, text: str) -> int:
    if name == "神铸赋形":
        return 302
    if "溯光祈愿" in text or "集录祈愿" in text:
        return 500
    return 0


def assign_character_gacha_types(events: list[dict[str, Any]], indexes: list[int]) -> None:
    grouped: dict[tuple[str, str], list[int]] = {}
    for index in indexes:
        event = events[index]
        grouped.setdefault((str(event.get("from") or ""), str(event.get("to") or "")), []).append(index)

    for group in grouped.values():
        for offset, index in enumerate(group):
            events[index]["type"] = 301 if offset == 0 else 400


def official_version_ranges(items: list[Any]) -> list[tuple[str, str, str]]:
    ranges: list[tuple[str, str, str]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        text = f"{item.get('title') or ''} {item.get('subtitle') or ''}"
        match = re.search(r"「([^」]+)」版本", text)
        if not match:
            continue
        start = official_time_to_iso(item.get("startsAt") or item.get("startTime"))
        end = official_time_to_iso(item.get("endsAt") or item.get("endTime"))
        if start and end:
            ranges.append((start, end, match.group(1)))
    return ranges


def official_version_for_event(start: str, ranges: list[tuple[str, str, str]]) -> str:
    event_time = parse_gacha_datetime(start)
    for range_start, range_end, label in ranges:
        if parse_gacha_datetime(range_start) <= event_time <= parse_gacha_datetime(range_end):
            return label
    if ranges:
        return ranges[0][2]
    return ""


def official_time_to_iso(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return ""
    if "T" in value:
        return value
    return value.replace(" ", "T") + "+08:00"


def clean_gacha_item_name(value: str) -> str:
    name = re.sub(r"[（(][^）)]*[）)]", "", value).strip()
    if "·" in name:
        name = name.split("·")[-1]
    return name.strip()


def id_lookup(items: list[dict[str, Any]]) -> dict[str, int]:
    result: dict[str, int] = {}
    for item in items:
        name = item.get("name")
        item_id = item.get("id")
        if isinstance(name, str) and isinstance(item_id, int):
            result[name] = item_id
    return result


def ids_for_names(names: list[str], lookup: dict[str, int]) -> list[int]:
    ids: list[int] = []
    for name in names:
        item_id = lookup.get(name)
        if isinstance(item_id, int) and item_id not in ids:
            ids.append(item_id)
    return ids


def resolve_materials(ids: list[int], material_names: dict[int, str]) -> list[str]:
    names: list[str] = []
    for item_id in ids:
        name = material_names.get(item_id)
        if name and name not in names:
            names.append(name)
    return names


def resolve_character_cultivation_materials(ids: list[int], material_names: dict[int, str]) -> dict[str, Any] | None:
    if len(ids) < 6:
        return None
    gem_id, boss_id, local_id, common_id, talent_book_id, weekly_id = ids[:6]
    cultivation = {
        "ascensionGemNames": resolve_tier_names(gem_id, 4, material_names),
        "bossMaterialName": material_names.get(boss_id, ""),
        "localSpecialtyName": material_names.get(local_id, ""),
        "commonMaterialNames": resolve_tier_names(common_id, 3, material_names),
        "talentBookNames": resolve_tier_names(talent_book_id, 3, material_names),
        "weeklyBossMaterialName": material_names.get(weekly_id, ""),
    }
    if (
        len(cultivation["ascensionGemNames"]) < 4
        or not cultivation["bossMaterialName"]
        or not cultivation["localSpecialtyName"]
        or len(cultivation["commonMaterialNames"]) < 3
        or len(cultivation["talentBookNames"]) < 3
        or not cultivation["weeklyBossMaterialName"]
    ):
        return None
    return cultivation


def resolve_tier_names(highest_id: int, tier_count: int, material_names: dict[int, str]) -> list[str]:
    start = highest_id - tier_count + 1
    return [
        material_names[item_id]
        for item_id in range(start, highest_id + 1)
        if item_id in material_names
    ]


def weapon_stat(weapon: dict[str, Any]) -> str:
    grow_curves = weapon.get("GrowCurves") or []
    if len(grow_curves) < 2:
        return "基础攻击力"
    return STAT_TYPES.get(grow_curves[1].get("Type"), "副属性")


def first_string(payload: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def add_asset_url(item: dict[str, Any], field: str, asset_name: str) -> None:
    if not asset_name:
        return
    if asset_name.startswith("http://") or asset_name.startswith("https://"):
        item[field] = asset_name
        return
    item[field] = f"{ASSET_BASE_URL}/{asset_name.removesuffix('.png')}.png"


def fetch_official_announcements_json(manual_dir: Path) -> Path:
    manual_dir.mkdir(parents=True, exist_ok=True)
    target = manual_dir / "official-announcements.raw.json"
    request = urllib.request.Request(
        OFFICIAL_ANNOUNCEMENTS_URL,
        headers={"User-Agent": "GenshinToolboxDataUpdater/1.0"},
    )
    with urlopen_with_certifi_fallback(request, timeout=20) as response:
        target.write_bytes(response.read())
    return target


def fetch_official_announcements_json_if_available(manual_dir: Path) -> Path | None:
    cached = manual_dir / "official-announcements.raw.json"
    try:
        return fetch_official_announcements_json(manual_dir)
    except Exception as error:
        if cached.exists():
            print(f"warning: official announcement fetch failed, using cached {cached}: {error}", file=sys.stderr)
            return cached
        print(f"warning: official announcement fetch failed, using manual announcements.json: {error}", file=sys.stderr)
        return None


def urlopen_with_certifi_fallback(request: urllib.request.Request, timeout: int):
    try:
        return urllib.request.urlopen(request, timeout=timeout)
    except urllib.error.URLError as error:
        reason = getattr(error, "reason", None)
        if not isinstance(reason, ssl.SSLCertVerificationError):
            raise
        try:
            import certifi  # type: ignore[import-not-found]
        except ImportError:
            raise
        context = ssl.create_default_context(cafile=certifi.where())
        return urllib.request.urlopen(request, timeout=timeout, context=context)


def empty_announcements(updated_at: str | None = None) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "updatedAt": updated_at or isoformat_z(datetime.now(timezone.utc)),
        "items": [],
    }


def package_release(public_dir: Path, release_dir: Path, generated: list[GeneratedFile]) -> Path:
    release_dir.mkdir(parents=True, exist_ok=True)
    manifest = read_json(public_dir / "manifest.json")
    stamp = (manifest.get("generatedAt") or isoformat_z(datetime.now(timezone.utc)))[:10].replace("-", ".")
    zip_path = release_dir / f"data-pack-{stamp}.zip"
    allowed = {item.path for item in generated}
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{zip_path.name}.",
        suffix=".tmp",
        dir=release_dir,
    )
    os.close(file_descriptor)
    temporary_zip = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(allowed):
                info = zipfile.ZipInfo(path)
                info.date_time = (1980, 1, 1, 0, 0, 0)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                archive.writestr(info, (public_dir / path).read_bytes())
        validate_release_archive(temporary_zip, public_dir, generated)
        os.replace(temporary_zip, zip_path)
    finally:
        temporary_zip.unlink(missing_ok=True)
    return zip_path


def validate_release_archive(zip_path: Path, public_dir: Path, generated: list[GeneratedFile]) -> None:
    expected = {item.path for item in generated}
    with zipfile.ZipFile(zip_path, "r") as archive:
        names = archive.namelist()
        if len(names) != len(set(names)) or set(names) != expected:
            raise RuntimeError(f"release archive members mismatch: expected {sorted(expected)}, got {sorted(names)}")
        bad_member = archive.testzip()
        if bad_member is not None:
            raise RuntimeError(f"release archive CRC check failed: {bad_member}")
        for path in expected:
            archived = archive.read(path)
            if archived != (public_dir / path).read_bytes():
                raise RuntimeError(f"release archive content mismatch: {path}")

        manifest = json.loads(archive.read("manifest.json"))
        records = manifest.get("files")
        if not isinstance(records, list):
            raise RuntimeError("release archive manifest files must be a list")
        expected_hashed = expected - {"manifest.json"}
        seen: set[str] = set()
        for record in records:
            if not isinstance(record, dict):
                raise RuntimeError("release archive manifest contains an invalid record")
            path = record.get("path")
            if path in seen or path not in expected_hashed:
                raise RuntimeError(f"release archive manifest contains an unexpected path: {path}")
            seen.add(path)
            digest = hashlib.sha256(archive.read(path)).hexdigest()
            if record.get("sha256") != digest:
                raise RuntimeError(f"release archive hash mismatch: {path}")
        if seen != expected_hashed:
            raise RuntimeError("release archive manifest is incomplete")


def commit_and_push(paths: list[Path], message: str, repository: Path | None = None) -> None:
    if repository is None:
        repository = Path(
            subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
        )
    repository = repository.expanduser().resolve()
    pathspecs = [str(path.expanduser().resolve().relative_to(repository)) for path in paths]
    staged = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "-z"],
        check=True,
        capture_output=True,
        cwd=repository,
    ).stdout.decode("utf-8").split("\0")
    unrelated = [path for path in staged if path and not any(path == spec or path.startswith(f"{spec}/") for spec in pathspecs)]
    if unrelated:
        raise RuntimeError(f"refusing to commit unrelated staged files: {', '.join(unrelated)}")

    run(["git", "add", "--", *pathspecs], cwd=repository)
    diff = subprocess.run(
        ["git", "diff", "--cached", "--quiet", "--", *pathspecs],
        check=False,
        cwd=repository,
    )
    if diff.returncode == 0:
        if has_unpushed_commits(repository):
            print("no generated data changes to commit; pushing existing unpushed commit")
            run(["git", "push"], cwd=repository)
        else:
            print("no generated data changes to commit")
        return
    run(["git", "commit", "--only", "-m", message, "--", *pathspecs], cwd=repository)
    run(["git", "push"], cwd=repository)


def has_unpushed_commits(repository: Path) -> bool:
    result = subprocess.run(
        ["git", "rev-list", "--count", "@{upstream}..HEAD"],
        check=False,
        capture_output=True,
        text=True,
        cwd=repository,
    )
    if result.returncode != 0:
        return False
    try:
        return int(result.stdout.strip()) > 0
    except ValueError:
        return False


def run_self_test() -> None:
    material_names = {
        104161: "哀叙冰玉碎屑",
        104162: "哀叙冰玉断片",
        104163: "哀叙冰玉块",
        104164: "哀叙冰玉",
        101202: "绯樱绣球",
        113023: "恒常机关之心",
        112044: "破旧的刀镡",
        112045: "影打刀镡",
        112046: "名刀镡",
        104323: "「风雅」的教导",
        104324: "「风雅」的指引",
        104325: "「风雅」的哲学",
        113018: "血玉之枝",
        114003: "远海夷地的瑚枝",
    }
    avatar = {
        "Id": 10000002,
        "Name": "神里绫华",
        "Quality": 5,
        "Weapon": 1,
        "Icon": "UI_AvatarIcon_Ayaka",
        "GachaCard": "UI_Gacha_AvatarImg_Ayaka",
        "CultivationItems": [104164, 113023, 101202, 112046, 104325, 113018],
        "FetterInfo": {"VisionBefore": "冰", "Association": 5},
    }
    weapon = {
        "Id": 11502,
        "Name": "雾切之回光",
        "WeaponType": 1,
        "RankLevel": 5,
        "Icon": "UI_EquipIcon_Sword_Narukami",
        "GrowCurves": [{"Type": 4}, {"Type": 22}],
        "CultivationItems": [114003],
    }
    assert convert_weapons([weapon], material_names)[0]["stat"] == "暴击伤害"
    assert convert_weapons([weapon], material_names)[0]["iconURL"].endswith("/UI_EquipIcon_Sword_Narukami.png")
    temp = Path(".cache/self-test-avatar")
    if temp.exists():
        shutil.rmtree(temp)
    temp.mkdir(parents=True)
    try:
        write_json(temp / "10000002.json", avatar)
        character = convert_characters(temp, material_names)[0]
        assert character["element"] == "冰"
        assert character["weaponType"] == "单手剑"
        assert character["iconURL"].endswith("/UI_AvatarIcon_Ayaka.png")
        assert character["portraitURL"].endswith("/UI_Gacha_AvatarImg_Ayaka.png")
        assert character["materials"] == ["哀叙冰玉", "恒常机关之心", "绯樱绣球", "名刀镡", "「风雅」的哲学", "血玉之枝"]
        assert character["cultivation"]["ascensionGemNames"] == ["哀叙冰玉碎屑", "哀叙冰玉断片", "哀叙冰玉块", "哀叙冰玉"]
        assert character["cultivation"]["commonMaterialNames"] == ["破旧的刀镡", "影打刀镡", "名刀镡"]
        assert character["cultivation"]["talentBookNames"] == ["「风雅」的教导", "「风雅」的指引", "「风雅」的哲学"]
    finally:
        shutil.rmtree(temp)

    official_announcements = convert_official_announcements(
        {
            "data": {
                "list": [
                    {
                        "type_label": "活动",
                        "list": [
                            {
                                "ann_id": 1,
                                "title": "祈愿活动开启",
                                "subtitle": "角色活动祈愿",
                                "start_time": "2026-06-24 10:00:00",
                                "end_time": "2026-07-15 17:59:59",
                            }
                        ],
                    }
                ]
            }
        }
    )
    assert official_announcements["items"][0]["title"] == "祈愿活动开启"
    official_gacha_announcements = convert_official_announcements(
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
                            },
                            {
                                "ann_id": 21744,
                                "title": "「星边夜语」祈愿：「白星黑曜·茜特菈莉(冰)」概率UP！",
                                "subtitle": "「星边夜语」祈愿",
                                "start_time": "2026-06-29 12:00:00",
                                "end_time": "2026-07-21 17:59:00",
                            },
                            {
                                "ann_id": 21745,
                                "title": "「神铸赋形」祈愿：「双手剑·超越之匙」「法器·祭星者之望」概率UP！",
                                "subtitle": "「神铸赋形」祈愿",
                                "start_time": "2026-06-29 12:00:00",
                                "end_time": "2026-07-21 17:59:00",
                            },
                        ],
                    },
                    {
                        "type_label": "游戏公告",
                        "list": [
                            {
                                "ann_id": 21788,
                                "title": "全新内容一览：地区·角色·祈愿·武器·衣装·剧情等",
                                "subtitle": "「月之八」版本现已开启",
                                "start_time": "2026-07-01 07:00:00",
                                "end_time": "2026-08-12 06:00:00",
                            }
                        ],
                    },
                ]
            }
        }
    )
    official_gacha_events = merge_official_gacha_events(
        [],
        official_gacha_announcements,
        characters=[
            {"id": 10002001, "name": "桑多涅"},
            {"id": 10000107, "name": "茜特菈莉"},
        ],
        weapons=[
            {"id": 12517, "name": "超越之匙"},
            {"id": 14517, "name": "祭星者之望"},
        ],
    )
    assert [(event["name"], event["type"]) for event in official_gacha_events] == [
        ("镜中的茶宴", 301),
        ("星边夜语", 400),
        ("神铸赋形", 302),
    ]
    assert official_gacha_events[0]["version"] == "月之八"
    assert official_gacha_events[0]["upOrangeList"] == [10002001]
    assert official_gacha_events[2]["upOrangeList"] == [12517, 14517]

    complete_snap_event = {
        "name": "镜中的茶宴",
        "version": "月之八",
        "type": 301,
        "from": "2026-06-29T12:00:00+08:00",
        "to": "2026-07-21T17:59:00+08:00",
        "upOrangeList": [10002001],
        "upPurpleList": [10000020, 10000031, 10000064],
        "banner": "https://snap.example/banner.jpg",
    }
    merged_complete_event = merge_official_gacha_events(
        [complete_snap_event],
        official_gacha_announcements,
        characters=[
            {"id": 10002001, "name": "桑多涅"},
            {"id": 10000107, "name": "茜特菈莉"},
        ],
        weapons=[
            {"id": 12517, "name": "超越之匙"},
            {"id": 14517, "name": "祭星者之望"},
        ],
    )[0]
    assert merged_complete_event["upPurpleList"] == [10000020, 10000031, 10000064]
    assert merged_complete_event["banner"] == "https://snap.example/banner.jpg"

    manual_payload = RemoteDataPayload(
        source="official-manual",
        version_prefix="manual",
        characters=[{"id": 10000002, "name": "神里绫华"}],
        weapons=[{"id": 11502, "name": "雾切之回光"}],
        materials=[{"id": 114003, "name": "远海夷地的瑚枝"}],
        gacha_events=[],
    )
    apply_asset_overrides(
        manual_payload,
        {
            "characters": [{"id": 10000002, "iconURL": "https://enka.network/ui/UI_AvatarIcon_Ayaka.png"}],
            "weapons": [{"id": 11502, "iconURL": "https://enka.network/ui/UI_EquipIcon_Sword_Narukami.png"}],
            "materials": [{"id": 114003, "iconURL": "https://enka.network/ui/UI_ItemIcon_114003.png"}],
        },
    )
    assert manual_payload.characters[0]["iconURL"].endswith("/UI_AvatarIcon_Ayaka.png")
    assert manual_payload.weapons[0]["iconURL"].endswith("/UI_EquipIcon_Sword_Narukami.png")
    assert manual_payload.materials[0]["iconURL"].endswith("/UI_ItemIcon_114003.png")

    temp_manual = Path(".cache/self-test-manual")
    if temp_manual.exists():
        shutil.rmtree(temp_manual)
    temp_manual.mkdir(parents=True)
    try:
        write_json(temp_manual / "characters.json", [{"id": 10000002, "name": "神里绫华"}])
        write_json(temp_manual / "weapons.json", [{"id": 11502, "name": "雾切之回光"}])
        write_json(temp_manual / "materials.json", [{"id": 114003, "name": "远海夷地的瑚枝"}])
        write_json(temp_manual / "gacha-events.json", [{"name": "手动卡池", "type": 301}])
        snap_gacha_events = [{"name": "Snap 卡池", "type": 301}]
        manual_with_snap_gacha = build_official_manual_payload(
            temp_manual,
            official_announcements_json=None,
            fetch_official_announcements=False,
            gacha_events_override=snap_gacha_events,
        )
        assert manual_with_snap_gacha.characters[0]["name"] == "神里绫华"
        assert manual_with_snap_gacha.gacha_events == snap_gacha_events

        stale_snap_gacha_events = [
            {"name": "旧 Snap 卡池", "type": 301, "to": "2026-06-09T17:59:00+08:00"}
        ]
        newer_manual_gacha_events = [
            {"name": "新手动卡池", "type": 301, "to": "2026-06-30T14:59:00+08:00"}
        ]
        assert (
            select_fresher_gacha_events(
                stale_snap_gacha_events,
                newer_manual_gacha_events,
                primary_label="Snap.Metadata",
                fallback_label="manual",
            )
            == newer_manual_gacha_events
        )
        assert (
            select_fresher_gacha_events(
                newer_manual_gacha_events,
                stale_snap_gacha_events,
                primary_label="Snap.Metadata",
                fallback_label="manual",
            )
            == newer_manual_gacha_events
        )
    finally:
        shutil.rmtree(temp_manual)

    temp_genshin_db = Path(".cache/self-test-genshin-db")
    if temp_genshin_db.exists():
        shutil.rmtree(temp_genshin_db)
    try:
        locale_dir = temp_genshin_db / "src" / "data" / "ChineseSimplified"
        image_dir = temp_genshin_db / "src" / "data" / "image"
        (locale_dir / "characters").mkdir(parents=True)
        (locale_dir / "talents").mkdir(parents=True)
        (locale_dir / "weapons").mkdir(parents=True)
        (locale_dir / "materials").mkdir(parents=True)
        image_dir.mkdir(parents=True)
        write_json(
            locale_dir / "characters" / "hutao.json",
            {
                "id": 10000046,
                "name": "胡桃",
                "elementText": "火",
                "weaponText": "长柄武器",
                "rarity": 5,
                "region": "璃月",
                "costs": {
                    "ascend1": [
                        {"id": 104111, "name": "燃愿玛瑙碎屑", "count": 1},
                        {"id": 100029, "name": "霓裳花", "count": 3},
                        {"id": 112038, "name": "骗骗花蜜", "count": 3},
                    ],
                    "ascend2": [
                        {"id": 104112, "name": "燃愿玛瑙断片", "count": 3},
                        {"id": 113016, "name": "未熟之玉", "count": 2},
                        {"id": 112039, "name": "微光花蜜", "count": 12},
                    ],
                    "ascend5": [
                        {"id": 104113, "name": "燃愿玛瑙块", "count": 6},
                        {"id": 112040, "name": "原素花蜜", "count": 12},
                    ],
                    "ascend6": [
                        {"id": 104114, "name": "燃愿玛瑙", "count": 6},
                    ],
                },
            },
        )
        write_json(
            locale_dir / "talents" / "hutao.json",
            {
                "id": 4601,
                "name": "胡桃",
                "costs": {
                    "lvl2": [
                        {"id": 104313, "name": "「勤劳」的教导", "count": 3},
                        {"id": 112038, "name": "骗骗花蜜", "count": 6},
                    ],
                    "lvl3": [
                        {"id": 104314, "name": "「勤劳」的指引", "count": 2},
                        {"id": 112039, "name": "微光花蜜", "count": 3},
                    ],
                    "lvl7": [
                        {"id": 104315, "name": "「勤劳」的哲学", "count": 4},
                        {"id": 112040, "name": "原素花蜜", "count": 4},
                        {"id": 113014, "name": "魔王之刃·残片", "count": 1},
                    ],
                    "lvl10": [
                        {"id": 104315, "name": "「勤劳」的哲学", "count": 16},
                        {"id": 113014, "name": "魔王之刃·残片", "count": 2},
                        {"id": 104319, "name": "智识之冕", "count": 1},
                    ],
                },
            },
        )
        write_json(
            locale_dir / "weapons" / "mistsplitterreforged.json",
            {
                "id": 11502,
                "name": "雾切之回光",
                "weaponText": "单手剑",
                "rarity": 5,
                "mainStatText": "暴击伤害",
                "costs": {"ascend6": [{"id": 114003, "name": "远海夷地的瑚枝", "count": 6}]},
            },
        )
        write_json(
            locale_dir / "materials" / "perpetualheart.json",
            {
                "id": 113023,
                "name": "恒常机关之心",
                "typeText": "角色培养素材",
                "description": "恒常机关阵列掉落的核心。",
            },
        )
        write_json(image_dir / "characters.json", {"hutao": {"filename_icon": "UI_AvatarIcon_Hutao", "filename_sideIcon": "UI_AvatarIcon_Side_Hutao"}})
        write_json(image_dir / "weapons.json", {"mistsplitterreforged": {"filename_icon": "UI_EquipIcon_Sword_Narukami"}})
        write_json(image_dir / "materials.json", {"perpetualheart": {"filename_icon": "UI_ItemIcon_113023"}})

        genshin_payload = build_genshin_db_payload(
            temp_genshin_db,
            gacha_events=[{"name": "Snap 卡池", "type": 301}],
            announcements=empty_announcements("2026-06-29T00:00:00Z"),
        )
        assert genshin_payload.source == "genshin-db"
        hu_tao = genshin_payload.characters[0]
        assert hu_tao["iconURL"].endswith("/UI_AvatarIcon_Hutao.png")
        assert hu_tao["cultivation"]["ascensionGemNames"] == ["燃愿玛瑙碎屑", "燃愿玛瑙断片", "燃愿玛瑙块", "燃愿玛瑙"]
        assert hu_tao["cultivation"]["bossMaterialName"] == "未熟之玉"
        assert hu_tao["cultivation"]["localSpecialtyName"] == "霓裳花"
        assert hu_tao["cultivation"]["commonMaterialNames"] == ["骗骗花蜜", "微光花蜜", "原素花蜜"]
        assert hu_tao["cultivation"]["talentBookNames"] == ["「勤劳」的教导", "「勤劳」的指引", "「勤劳」的哲学"]
        assert "智识之冕" not in hu_tao["cultivation"]["talentBookNames"]
        assert hu_tao["cultivation"]["weeklyBossMaterialName"] == "魔王之刃·残片"
        assert "魔王之刃·残片" in hu_tao["materials"]
        assert genshin_payload.weapons[0]["iconURL"].endswith("/UI_EquipIcon_Sword_Narukami.png")
        assert genshin_payload.materials[0]["iconURL"].endswith("/UI_ItemIcon_113023.png")
        assert genshin_payload.gacha_events[0]["name"] == "Snap 卡池"
    finally:
        shutil.rmtree(temp_genshin_db)


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as file:
        return json.load(file)


def read_json_if_exists(path: Path) -> Any | None:
    if not path.exists():
        return None
    return read_json(path)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2, sort_keys=True)
        file.write("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def isoformat_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run(command: list[str], cwd: Path | None = None) -> None:
    print("+", " ".join(command))
    subprocess.run(command, check=True, cwd=cwd)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error
