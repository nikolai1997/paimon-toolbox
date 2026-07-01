# 派蒙工具箱数据更新工具

这个文件夹用于独立更新资料库数据，并生成可发布到 GitHub Pages 的 JSON 文件和可上传网盘的离线数据包。

## 基本用法

在这个工具文件夹内运行：

```bash
./run_data_update.command
```

等价于：

```bash
python3 update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --manual-dir data/manual \
  --fetch-official-announcements \
  --public-dir data/public \
  --release-dir data/releases
```

当前数据来源：

```text
角色、武器、材料：theBowja/genshin-db
角色天赋素材：theBowja/genshin-db 的 talents 目录
卡池/复刻：SnapHutaoRemasteringProject/Snap.Metadata 的 GachaEvent.json
公告：米哈游官方公告接口，失败时使用本地缓存
```

如果只想使用本地手动补丁源，可以运行：

```bash
python3 update_remote_data.py --source official-manual --manual-dir data/manual
```

本地手动补丁源会读取：

```text
data/manual/characters.json
data/manual/weapons.json
data/manual/materials.json
data/manual/gacha-events.json
data/manual/announcements.json
```

其中公告可以额外接入官方公告原始 JSON：

```bash
python3 update_remote_data.py --source official-manual --manual-dir data/manual --fetch-official-announcements
```

注意：官方公告只能提供公告/活动类公开信息，不能完整替代角色、武器、材料数据库；这些结构化资料仍需要 `data/manual/*.json` 维护。

生成结果：

```text
data/public/
data/releases/data-pack-YYYY.MM.DD.zip
```

`data/public/` 适合提交到 GitHub Pages。

`data/releases/data-pack-YYYY.MM.DD.zip` 适合上传 GitHub Release 或网盘，给国内用户手动下载后在 App 设置页导入。

## 只用已有上游缓存

如果本机已有上游缓存，可跳过拉取：

```bash
python3 update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --skip-fetch
```

## 自检

```bash
python3 update_remote_data.py --self-test
```

看到 `self-test passed` 说明转换逻辑可用。

## 自动提交到 GitHub

确认本地 git 已经配置好远程仓库后，可以运行：

```bash
python3 update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --manual-dir data/manual \
  --fetch-official-announcements \
  --push
```

注意：`--push` 会执行 `git add`、`git commit`、`git push`。

## 国内兜底流程

1. 运行更新工具生成 `data-pack-YYYY.MM.DD.zip`。
2. 把 zip 上传到网盘。
3. 用户从网盘下载 zip。
4. 用户在 App 的设置页点击“导入 data-pack.zip”。
