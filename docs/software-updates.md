# 软件更新发布

软件更新与 `data-pack.zip` 资料更新分别发布。安装包使用 Sparkle 2.10.1 校验和安装。

## App 行为

- 默认每天自动检查正式版本，支持自动下载。
- “设置 > 软件更新”提供“自动更新软件”开关及“检查软件更新”按钮。关闭开关会同时关闭后台检查和下载，不影响手动检查；选择在重启后保留。
- 自动检查和下载只使用 GitHub。连接或下载失败时，提示打开夸克网盘手动下载安装包。
- 普通网盘分享页不作为 appcast 或安装包解析，签名校验失败不触发网盘回退。
- 安装时间由 Sparkle 的原生更新界面管理，包括安装并重启或退出时安装。

## 发布正式版本

`VERSION` 同时用于软件展示版本、构建版本、DMG 名称和更新版本比较。
自动更新功能的首个版本为 `0.1.6`。后续版本号由维护者确认后再修改，不自动递增。

仓库配置 `SPARKLE_ED25519_PRIVATE_KEY` Secret 后，提交代码并推送匹配的 `v版本号` 标签，
`Publish software update` 工作流会构建通用安装包、签名更新、上传附件并发布 Release。
更新入口为软件仓库最新正式 Release 的 `appcast.xml` 附件。

本机发布文件可使用以下步骤生成：

```sh
./script/package_dmg.sh
python3 script/prepare_software_update.py --notes docs/releases/版本号.md
```

结果位于 `dist/software-update/`。将其中的 `appcast.xml`、`software-latest.json`
与相同版本的 DMG 一起上传到正式 Release。旧 Release 只有 DMG 时不支持自动安装。

本机签名密钥位于登录钥匙串，账户名称为 `com.nikolai.paimon-toolbox`。
发布工作流使用同一私钥对应的 Secret。公开验证公钥保存在 `Resources/software-update.json`。

## 网盘分工

软件备用下载使用 `Resources/software-update.json` 中的 `quarkShareURL`。
夸克安装包目录为“软件/派蒙工具箱”，分享链接保持不变。
软件版本号保持 `0.1.6`；夸克仅保留最近 3 个版本。
每次在本机发布时，同步上传与 GitHub Release 完全相同的 DMG；不依赖定时任务，
不向 GitHub 配置夸克账号授权。使用官方网盘工具上传，上传完成后核对目录中的文件大小。
当前工具没有删除命令；超过 3 版时，通过网盘页面删除最旧版本，不删除其他目录的文件。

本机发布顺序：确认版本号、构建及测试、生成更新签名、上传 GitHub Release 附件、
上传同一份 DMG 至夸克、核对两边文件、清理夸克旧版，再完成发布核对。
再次发布相同版本前必须先核对网盘已有文件，不重复上传生成同名副本。

坚果云继续分发离线资料包。资料库更新任务在上传成功后核对新日期包及
`data-pack-latest.zip` 的大小，再清理旧日期包，保留最近 7 份及 latest。
清理仅处理 `GenshinToolbox` 当前层合法日期格式的资料包，不递归，不处理安装包。
软件安装包的坚果云镜像任务停用，已上传文件不自动删除。
