# 派蒙工具箱数据更新工具

这个文件夹用于独立更新资料库数据，并生成可发布到 GitHub Pages 的 JSON 文件和可上传网盘的离线数据包。

## 基本用法

在仓库根目录运行：

```bash
./script/run_data_update.command
```

也可以在任意目录使用 `run_data_update.command` 的绝对路径调用。工具始终以 `update_remote_data.py` 所在的仓库根目录为 root，不依赖当前工作目录。

等价于：

```bash
python3 script/update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --manual-dir data/manual \
  --fetch-official-announcements \
  --public-dir data/public \
  --release-dir data/releases
```

`--source-cache`、`--genshin-db-cache`、`--manual-dir`、`--official-announcements-json`、`--public-dir` 和 `--release-dir` 的显式相对路径也都相对仓库根目录解析。

当前数据来源：

```text
角色、武器、材料：theBowja/genshin-db
角色天赋素材：theBowja/genshin-db 的 talents 目录
卡池/复刻：SnapHutaoRemasteringProject/Snap.Metadata 的 GachaEvent.json
公告：米哈游官方公告接口，失败时使用本地缓存
```

如果只想使用本地手动补丁源，可以运行：

```bash
python3 script/update_remote_data.py --source official-manual --manual-dir data/manual
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
python3 script/update_remote_data.py --source official-manual --manual-dir data/manual --fetch-official-announcements
```

注意：官方公告只能提供公告/活动类公开信息，不能完整替代角色、武器、材料数据库；这些结构化资料仍需要 `data/manual/*.json` 维护。

生成结果：

```text
data/public/
data/releases/data-pack-YYYY.MM.DD.zip
```

`data/public/` 适合提交到 GitHub Pages。

工具会先在 `data/public/` 同文件系统的临时目录中生成并校验全部 JSON 和 `manifest.json`，通过后才替换正式目录；生成或校验失败时保留原目录。

`data/releases/data-pack-YYYY.MM.DD.zip` 适合上传 GitHub Release 或网盘，给国内用户手动下载后在 App 设置页导入。

ZIP 同样会先写入同目录临时文件，校验成员、内容和 manifest hash 后再替换目标 ZIP；失败时不会预先删除旧 ZIP。

## 只用已有上游缓存

如果本机已有上游缓存，可跳过拉取：

```bash
python3 script/update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --skip-fetch
```

## 自检

```bash
python3 script/update_remote_data.py --self-test
```

看到 `self-test passed` 说明转换逻辑可用。

## 自动提交到 GitHub

确认本地 git 已经配置好远程仓库后，可以运行：

```bash
python3 script/update_remote_data.py \
  --source genshin-db \
  --gacha-source snap-metadata \
  --manual-dir data/manual \
  --fetch-official-announcements \
  --push
```

注意：`--push` 会对 `data/public/` 执行 `git add`、`git commit`、`git push`。`data/releases/*.zip` 会继续生成在本机，用于上传 GitHub Release 或网盘，不随 `--push` 提交。如果前一次已成功 commit 但 push 失败，下次运行即使没有新 diff，也会检测并推送尚未推送的提交。存在无关的已暂存文件时仍会拒绝执行。

## 国内兜底流程

1. 运行更新工具生成 `data-pack-YYYY.MM.DD.zip`。
2. 把 zip 上传到网盘。
3. 用户从网盘下载 zip。
4. 用户在 App 的设置页点击“导入 data-pack.zip”。
