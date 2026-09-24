# ModLoader 外置记忆

> 2026-09-24：v2.3.0（settings v0.4.0）通用可展开分组已安装，MSW v1.13.1首个接入；最终文件安装前后各65项通过。

## 1. 这个模组是什么
三部分：MainFE清单引导v2、Windows扫描器v2.1、运行模块ModLoaderMod v2.3.0。设置源码src/settings，入口src/runtime与release/ModLoaderMod.swf；不再从旧ModSettings项目构建。设置值和保存仍归客户端，两级菜单、分组显示和位置记忆由宿主管理。

## 2. 用户偏好与协作约定
- 合并Q1–Q4确认A：内置设置、保留接口/记忆、仅支持1.02；不加模组管理，已完成。
- 分组Q1–Q6均A并整体确认实现、验证、安装：大类逐行，子项下展；标题全选/清空，部分选中点击补全；最多展开一类或全部收起，跨重启记忆；只改Pip，F6平面列表保留。完整见design/grouped-settings.md。
- 扫描器只更新名单，不启动游戏；未知模组默认三个版本全开，已知限制写supported-mods.txt。
- 隔离测试使用唯一AIR应用ID、隐藏窗口、自有存储，只终止自己启动的进程。本环境启动AIR需正常桌面/提权环境；不操作用户游戏或存档。
- 游戏SWF改动须独立走补丁门禁；本轮只安装已授权的ModLoader和MSW两包，受保护治理文件未改。

## 3. 当前状态
- 正式ModLoaderMod.swf：17282字节，SHA256 `375951AE86BCCD8886CDEAC8B479A339877CEE30F5D1B489C21FE06C736C0BF5`。
- 同时安装MSW v1.13.1-settings-groups：54503字节，SHA256 `E1EA2AC2ACAA1F9F7D91DC9EFE72F07E782609EB1C8B4E5ED42072FB1C53FE28`，包含同期激光笔fa8c1ee；不能用旧B8EB/C233产物覆盖。
- registerPage的navigation.groups可选；groupVersion=1，apiVersion/menuVersion仍1。getPages().items保持平面，重置含收起项；旧客户端/旧宿主兼容。展开ID存于原ModSettingsMenu（/）expandedGroups，不能迁到每次启动清空的ModLoader诊断存储。
- 跨三进程62+6+4项、旧宿主8项、旧客户端及新组合各50项；最终精确宿主中文样式24项、安装前后各65项与frames=600通过。MSW准确生产字节规则1197项、豁免320项、多锁52项、激光真实存读档/开火通过。早期宿主与最终三角箭头版本的验证界限见实验记录。
- 新入口1/0/0、旧ModSettings入口0/0/0，总数7/3/2。三份游戏SWF、清单/版本表、其他包与文本配置15个保护项哈希不变。build/out/groups-installation/deployment.json为installed-and-verified。
- 首次内置v2.2的记忆迁移71、无MSW20、中文24、三版本故障94、前后50是历史证据，见settings-merge-2026-09-24.md。

## 4. 正在进行与卡点
分组实现、验证和安装均完成，无待确认/安装步骤。设置后续只维护本项目；旧ModSettings保留历史。MSW仓他人的journal历史重排和新建测试文件未纳入本轮提交。

## 5. 已知边界
- 设置仅1.02；本轮不认证DLC设置、全部联机/战斗、完整激光笔/炮塔/时停组合。保留MSW原已知玩法边界。
- 清单顺序只决定发起请求先后，初始化异步；客户端继续重试。缺包/同步init失败不阻止其他请求，不保证任意后续异步错误隔离。
- 禁止两个设置宿主同时启用；旧ModSettings包存在时必须保留禁用登记。扫描器不证明未知入口或跨版本兼容。
- 根AGENTS和部分技能仍描述旧加载结构，本项目无AGENT_SCOPE，受保护资料由用户维护。

## 6. 回滚与下一步
- 当前成对回滚：work/backups/before-groups-20260924-075628/。保存退出游戏，分别恢复两个SWF到各自release，再重启；恢复ModLoader2.2/C970和含激光笔的MSW1.13.0/476430。无需改名单、版本表或配置。
- 用户保存退出并重启后，在「模组→MSW→锁定豁免」使用类别批量按钮和展开箭头；原勾选保留，首次全部收起。
- ./build/build.ps1只输出build/out，上线仍需备份与门禁。取当前正式客户端，不用旧冻结MSW覆盖新功能。
- 如要撤回首次设置合并，按README的历史合并回滚段协调新旧入口与扫描；不是当前分组回滚。Steam更新按README恢复补丁，不为设置更新重打MainFE。

## 7. 深入了解
- docs/settings-interface.md：完整分组API、兼容与记忆契约；design/grouped-settings.md：确认方案。
- knowledge/experiments/grouped-settings-2026-09-24.md：行为、精确产物对应测试、失败探针修正、安装与回滚；state/journal.md：近期实施。
- build/test-menus.ps1 -Probe GroupProbe：分组三进程测试；-MSWSwf/-HostSwf测试候选与兼容；-InstalledHost -SmokeOnly复验正式文件。MenuProbe保留原菜单回归。
- build/test-button-style.ps1：中文像素和页面切换；test-startup.ps1：三版本及故障；tools/test_loader.ps1/test_scanner.ps1：离线回归；smoke_test.ps1：加载冒烟。
- knowledge/experiments/settings-merge-2026-09-24.md：首次合并；knowledge/discoveries/loader-review-2026-09-23.md：v2引导修复；tools/patch_game_swfs.ps1：补丁；src/ModScanner.cs：扫描器。
