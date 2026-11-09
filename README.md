<p align="center">
  <img src="docs/assets/app-icon.png" alt="派蒙工具箱图标" width="128">
</p>

# 派蒙工具箱

派蒙工具箱是一个 macOS 原神工具应用，当前包含资料库、祈愿记录分析、角色培养规划、米游社与 HoYoLAB 登录签到、实时便签、桌面摆件连接、桌面小组件和远程数据更新能力。

本项目是非官方工具，和 HoYoverse / 米哈游没有从属关系。

![派蒙工具箱总览](docs/assets/app-overview.png)

## 功能

- 角色、武器、材料资料库
- 角色养成材料与培养规划
- 祈愿记录导入、统计和复刻间隔展示
- 米游社扫码登录与每日签到
- HoYoLAB 国际服网页登录或 Cookie 导入，支持亚洲、美洲、欧洲、港澳台服务器
- 实时便签：原粹树脂、每日委托和探索派遣状态
- 官方公告正文阅读
- 局域网桌面 ESP 摆件发现、配对与状态同步
- macOS 桌面小组件
- GitHub Pages 在线数据更新
- 离线 `data-pack-YYYY.MM.DD.zip` 导入兜底

## HoYoLAB 国际服

1. 在“账号与签到”选择 **HoYoLAB 登录 · 国际服**。
2. 选择服务器（默认 **Asia / 亚洲**），在内嵌的 HoYoLAB 官方网页登录。
3. 点击“已登录，连接账号”，工具箱会读取该网页会话中的 HoYoLAB Cookie 并查找对应服务器的角色。
4. 首页显示实时便签；“账号与签到”可刷新签到状态、领取每日奖励。账号页也可重新登录或更换服务器。

网页登录不可用时，可切换“导入 Cookie”：在浏览器登录 `hoyolab.com`，打开开发者工具的 Network 面板，复制已登录请求的 `Cookie` 请求头，粘贴到工具箱中。支持原始 v1/v2 Cookie，通常包含 `ltuid_v2`、`ltoken_v2` 和 `ltmid_v2`。凭据只在本机加密保存，不要发给他人；关闭登录窗口会清除内嵌网页会话。

自动同步祈愿还需要 `cookie_token_v2`、`account_id_v2` 和 `account_mid_v2`。网页会话没有这些字段时，可导入完整 Cookie，或继续使用手动 UIGF 导入。

点击“从账号更新”后，会显示当前卡池、页数、已读取条数和耗时；遇到限流会提示自动重试。读取期间可以取消，取消不会覆盖已有祈愿记录。

若实时便签未启用，请先在 HoYoLAB 战绩中启用。触发安全验证时，在 HoYoLAB 官方网页完成后返回工具箱刷新；登录过期需要重新登录。米游社补签不适用于 HoYoLAB。角色、武器资料和公告仍使用现有中文数据源。

国际服接口参考 [genshin.py 的路由](https://github.com/seriaati/genshin.py/blob/master/genshin/client/routes.py)与[认证说明](https://seria.is-a.dev/genshin.py/authentication/)。

## 本地运行

需要 macOS 14+ 和 Xcode（Swift 6）：

```bash
bash script/build_and_run.sh
swift test --disable-sandbox
```

## 数据来源

App 默认从公开数据仓库读取生成后的 JSON：

```txt
https://nikolai1997.github.io/paimon-toolbox-data/metadata.json
```

当前数据生成链路见 [docs/data-source-configuration.md](docs/data-source-configuration.md)。

基础资料主要来自公开项目 `theBowja/genshin-db`，卡池信息来自 `SnapHutaoRemasteringProject/Snap.Metadata`，公告来自米哈游官方公告接口。生成后的数据由独立数据仓库发布，App 不直接依赖上游项目运行。

## 安装

当前发布包没有使用 Developer ID 签名，也未经过 Apple 公证。首次打开时，macOS 会提示无法验证开发者，这是未公证 App 的系统行为。

1. 打开 DMG，把“派蒙工具箱”拖入“应用程序”。
2. 在 Finder 的“应用程序”中右键“派蒙工具箱”，选择“打开”。
3. 在再次出现的提示中选择“打开”。
4. 如果仍被阻止，进入“系统设置” > “隐私与安全性”，在安全性提示旁选择“仍要打开”。

请只从本项目的 GitHub Releases 获取安装包。每次更新后，macOS 可能会再次要求确认。

## 许可证

代码以 MIT License 开源。第三方项目的版权与许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。游戏素材、名称、图标和公告的权利归其各自权利方所有。
