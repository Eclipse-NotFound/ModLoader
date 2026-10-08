# GitHub 玩家文档更新 · 2026-10-08

- 用户请求：所有已公开模组页面统一改善普通玩家指引。
- 仓库：[ModLoader](https://github.com/Eclipse-NotFound/ModLoader)。
- 公开文档提交：[94d419c](https://github.com/Eclipse-NotFound/ModLoader/commit/94d419c125d73e31039094ec82ae479f7de25b2e)；基线 5b8ee7e03187317569fe2023fba96400f658290a。
- 本地接入前提交：e6c5cf8f89eea7184a2dc82aa9dd441c14c9d998。公开提交来自远端文档副本，本地开发提交未随本次发布推送。
- 修改文件：`README.md`、`README.zh-CN.md`、`docs/DEVELOPMENT.zh-CN.md`、`docs/INSTALL.md`、`docs/INSTALL.zh-CN.md`。
- 仓库简介同步更新为：Start here: install Remains mods | 模组安装入门、加载器与游戏内设置。
- 内容：成品直达下载与 Assets 说明、首次前置和扫描步骤、首次玩法、配置保留、停用恢复、常见问题及反馈入口；明确公开包与源码进度的区别。
- 核验：八仓23份文档、231处链接静态核对通过；16个首页使用 GitHub GFM 渲染器确认标题/下载/折叠区；线上23个文件 Git blob 与提交逐项相同，简介读回一致。下载包已只读检查，没有运行安装器。
- 验证边界：纯文档改动，未重跑游戏、构建或发布任何二进制。RConnect 公开包仍0.2.8，RModifier仍0.4.0；开发版能力不能当作下载版能力。
- 记录归属：本条与 MEMORY/journal 只在本地保存；远端本轮仅含玩家文档。
