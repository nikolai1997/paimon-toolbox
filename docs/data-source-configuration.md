# 数据源配置说明

本文档记录派蒙工具箱当前使用的公开数据来源和生成产物。

## App 使用的数据入口

App 不向用户展示数据源 URL。用户只需要在设置里开启“启动时自动从 GitHub 更新”，App 会使用内置地址拉取资料库。

当前内置地址：

```txt
https://nikolai1997.github.io/paimon-toolbox-data/metadata.json
```

相关代码：

```txt
Support/RemoteDataSettings.swift
```

离线资料包兜底地址保存在同一个设置文件中。GitHub 无法访问时，用户可以手动下载 `data-pack-latest.zip` 并在 App 内导入。

## GitHub 数据仓库

数据仓库：

```txt
https://github.com/nikolai1997/paimon-toolbox-data
```

App 只访问你自己的 GitHub Pages，不直接访问任何上游项目。

## 当前上游来源

当前生成命令：

```bash
python3 tools/update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --manual-dir data/manual \
  --fetch-official-announcements \
  --public-dir data/public \
  --release-dir data/releases
```

各类数据来源：

| 数据类型 | 当前来源 | 说明 |
|---|---|---|
| 角色、武器、材料 | `theBowja/genshin-db` | 基础资料库主来源。当前生成结果为角色 119、武器 236、材料 849。角色养成素材由 `characters/` 的突破消耗和 `talents/` 的天赋消耗共同生成。 |
| 卡池信息 | `SnapHutaoRemasteringProject/Snap.Metadata` | 使用 `Genshin/CHS/GachaEvent.json`，用于当前卡池、历史卡池和复刻统计。 |
| 公告 | 米哈游官方公告接口 | 更新脚本抓取，并缓存到 `data/manual/official-announcements.raw.json`。 |
| 图片 URL | 上游图片字段 + Enka URL 规则 | 生成器补齐 `iconURL` / `portraitURL`。 |

当前素材覆盖情况：

- 角色、武器、材料图片：全部有 URL。
- 常规角色养成素材：115 / 119 个角色完整覆盖突破宝石、Boss 材料、本地特产、普通素材、天赋书、周本材料。
- 特殊例外：空、荧没有传统 Boss/周本三件套；`奇偶·男性`、`奇偶·女性` 当前上游只有天赋材料，缺突破材料。

当前线上 `config.json` 标记：

```json
{
  "dataSource": "genshin-db",
  "preferredUpdateChannel": "github-pages"
}
```

## 更新节奏

数据仓库会定期生成公开 JSON 和离线资料包。App 启动时可自动检查线上资料库；无法访问线上地址时，可使用离线资料包导入。

## 生成产物

GitHub Pages 发布目录：

```txt
data/public/
```

主要文件：

| 文件 | 用途 |
|---|---|
| `metadata.json` | App 资料库主文件，包含角色、武器、材料。 |
| `characters.json` | 独立角色数据。 |
| `weapons.json` | 独立武器数据。 |
| `materials.json` | 独立材料数据。 |
| `gacha-events.json` | 卡池历史和当前卡池数据。 |
| `announcements.json` | 公告数据。 |
| `config.json` | 远程配置。 |
| `latest.json` | 数据版本检查。 |
| `manifest.json` | 文件校验清单。 |

离线包输出目录：

```txt
data/releases/
```

离线包文件名固定为：

```txt
data-pack-latest.zip
```

## 兜底逻辑

基础资料：

- 主路径：从 `genshin-db` 拉取。
- 如果上游拉取失败，本次 Actions 会失败，不会生成错误数据。

卡池数据：

- 主路径：从 `Snap.Metadata` 拉取 `GachaEvent.json`。
- 如果 Snap.Metadata 拉取失败，脚本会回退到：

```txt
data/manual/gacha-events.json
```

公告数据：

- 主路径：从米哈游官方公告接口抓取。
- 如果抓取失败，优先使用已缓存的：

```txt
data/manual/official-announcements.raw.json
```

再失败则使用：

```txt
data/manual/announcements.json
```

## 本地数据

数据仓库生成后，App 仓库内也保留一份本地数据，便于开发、测试和离线内置基础数据：

```txt
<app-repo>/data/public/
<app-repo>/Resources/metadata.sample.json
```

`Resources/metadata.sample.json` 是 App 内置基础资料库。在线更新失败时，App 仍可用这份基础数据启动。
