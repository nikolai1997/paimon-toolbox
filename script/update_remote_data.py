#!/usr/bin/env python3
"""Generate public remote-data JSON and an offline data-pack zip."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import ssl
import subprocess
import sys
import urllib.error
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
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        print("self-test passed")
        return 0

    root = Path.cwd()
    source_cache = root / args.source_cache
    genshin_db_cache = root / args.genshin_db_cache
    manual_dir = root / args.manual_dir
    public_dir = root / args.public_dir
    release_dir = root / args.release_dir

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
                print(f"warning: Snap.Metadata gacha fetch failed, using manual gacha-events.json: {error}", file=sys.stderr)
        payload = build_official_manual_payload(
            manual_dir,
            official_announcements_json=Path(args.official_announcements_json) if args.official_announcements_json else None,
            fetch_official_announcements=args.fetch_official_announcements,
            gacha_events_override=gacha_events_override,
        )
    else:
        announcements = load_announcements(
            manual_dir,
            official_announcements_json=Path(args.official_announcements_json) if args.official_announcements_json else None,
            fetch_official_announcements=args.fetch_official_announcements,
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
                print(f"warning: Snap.Metadata gacha fetch failed, using manual gacha-events.json: {error}", file=sys.stderr)
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
        commit_and_push([public_dir, zip_path], args.commit_message)

    return 0


def ensure_source_checkout(source_cache: Path, skip_fetch: bool) -> None:
    ensure_git_checkout(SNAP_METADATA_REPO_URL, source_cache, skip_fetch=skip_fetch)


def ensure_genshin_db_checkout(source_cache: Path, skip_fetch: bool) -> None:
    ensure_git_checkout(GENSHIN_DB_REPO_URL, source_cache, skip_fetch=skip_fetch, sparse_paths=GENSHIN_DB_SPARSE_PATHS)


def ensure_git_checkout(repo_url: str, source_cache: Path, skip_fetch: bool, sparse_paths: list[str] | None = None) -> None:
    if skip_fetch:
        if not source_cache.exists():
            raise SystemExit(f"{source_cache} does not exist; rerun without --skip-fetch")
        return

    source_cache.parent.mkdir(parents=True, exist_ok=True)
    if (source_cache / ".git").exists():
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
) -> dict[str, Any]:
    announcements = read_json_if_exists(manual_dir / "announcements.json") or empty_announcements()
    official_json_path = official_announcements_json
    if fetch_official_announcements:
        official_json_path = fetch_official_announcements_json_if_available(manual_dir)
    if official_json_path is not None:
        return convert_official_announcements(read_json(official_json_path))
    return announcements


def build_official_manual_payload(
    manual_dir: Path,
    official_announcements_json: Path | None,
    fetch_official_announcements: bool,
    gacha_events_override: list[dict[str, Any]] | None = None,
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
    public_dir.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    announcements = payload.announcements or empty_announcements()
    previous_metadata = read_json_if_exists(public_dir / "metadata.json") or {}
    apply_asset_overrides(payload, previous_metadata)
    previous_announcements = read_json_if_exists(public_dir / "announcements.json") or {}
    previous_gacha_events = read_json_if_exists(public_dir / "gacha-events.json") or []
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
    for file_name, kind, payload in files:
        write_json(public_dir / file_name, payload)
        generated.append(GeneratedFile(file_name, kind))

    manifest = {
        "schemaVersion": 1,
        "generatedAt": metadata["updatedAt"],
        "files": [
            {
                "path": item.path,
                "sha256": sha256_file(public_dir / item.path),
                "kind": item.kind,
            }
            for item in generated
        ],
    }
    write_json(public_dir / "manifest.json", manifest)
    generated.append(GeneratedFile("manifest.json", "manifest"))
    return generated


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
        image_payload = image_index.get(path.stem) if isinstance(image_index, dict) else None
        if isinstance(image_payload, dict):
            add_asset_url(item, "iconURL", first_string(image_payload, "filename_icon"))
        weapons.append(item)
    return sorted(weapons, key=lambda item: (item["rarity"], item["id"]), reverse=True)


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
                    "banner": announcement.get("banner", ""),
                    "contentURL": announcement.get("content_url", ""),
                }
            )
    return {
        "schemaVersion": 1,
        "updatedAt": isoformat_z(datetime.now(timezone.utc)),
        "items": items,
    }


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
    for event in [*events, *official_events]:
        key = (int(event.get("type") or 0), str(event.get("name") or ""), str(event.get("from") or ""))
        if key not in merged:
            order.append(key)
        merged[key] = event
    return [merged[key] for key in order]


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

        start = official_time_to_iso(item.get("startTime"))
        end = official_time_to_iso(item.get("endTime"))
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
        start = official_time_to_iso(item.get("startTime"))
        end = official_time_to_iso(item.get("endTime"))
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
    if zip_path.exists():
        zip_path.unlink()

    allowed = {item.path for item in generated}
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(allowed):
            info = zipfile.ZipInfo(path)
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, (public_dir / path).read_bytes())
    return zip_path


def commit_and_push(paths: list[Path], message: str) -> None:
    run(["git", "add", *[str(path) for path in paths]])
    diff = subprocess.run(["git", "diff", "--cached", "--quiet"], check=False)
    if diff.returncode == 0:
        print("no generated data changes to commit")
        return
    run(["git", "commit", "-m", message])
    run(["git", "push"])


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


def run(command: list[str]) -> None:
    print("+", " ".join(command))
    subprocess.run(command, check=True)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error
