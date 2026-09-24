---
domain: ui-systems
type: experiments
game-version: ["1.02"]
confidence: high
verified: true
discovered-by: ModLoader
evidence:
  - kind: runtime-experiment
    summary: "独立AIR实例实际控件、三次启动记忆、旧宿主/旧客户端兼容；最终字节中文样式24项、安装前后各65项与600帧心跳。"
date-updated: 2026-09-24
---

# 可展开分组：实现、兼容与安装

用户Q1–Q6均A并确认实现、验证、安装。设计见../../design/grouped-settings.md，接口见../../docs/settings-interface.md。2026-09-24已安装ModLoader v2.3.0（settings v0.4.0）和MSW v1.13.1-settings-groups。

## 行为和实现

registerPage原六参数保留；第六参数navigation增加可选groups，能力groupVersion=1。每组以稳定ID、标签、成员keys、可选短标签及setAll(Boolean)登记。原getPages().items保持平面列表，旧消费者和resetPage继续遍历全部原项。分组定义在更改现有页前统一校验，显式坏定义拒绝整次登记，旧五参数刷新保留并重新绑定有效分组。

标题批量按钮与展开箭头分离；部分或全未选时补全，全选时清空，计数从客户端回调重读。每页最多展开一组，可全部收起；展开ID保存于原ModSettingsMenu（路径/），缺席/迟到登记不抹除记录。滑杆可放入只折叠组；带setAll的组仅接受check项。通用长组沿16行上限分页。

MSW使用原5类31项，不增加配置键或过滤层；每次整类操作修改本类原键并仅save一次。最大展开14行；恢复默认清全部31项，包括收起项，保留展开位置。F6保留平面列表与五功能页。客户端检测能力，旧宿主继续平面显示。

## 精确构建与测试

最终正式ModLoader：17282字节，SHA256 `375951AE86BCCD8886CDEAC8B479A339877CEE30F5D1B489C21FE06C736C0BF5`。
最终正式MSW：54503字节，SHA256 `E1EA2AC2ACAA1F9F7D91DC9EFE72F07E782609EB1C8B4E5ED42072FB1C53FE28`，40生产定义，无宿主类或探针混入。

MSW以当前fa8c1ee源代码为基线，包含同期完成的激光笔；冻结在work/groups-source/src，最终核对与MSW当前源码一致。测试只用独立应用ID、自有存储和隐藏进程，不操作用户进程或真实存档。

| 记录（build/out下） | 结果与覆盖 |
|---|---|
| menus/groups-verified | 62+6+4项；三态、真实按钮/子项、整类及兄弟组独立、默认值、功能/关闭记忆、跨进程展开及显式全收起、滑杆、40子项分页、错误登记、旧五参数与迟到登记 |
| menus/groups-old-host-verified | 8项；新MSW配旧C970宿主，31项平面入口、F6及旧版本心跳 |
| menus/groups-old-client | 50项；新宿主配旧正式MSW476430，原菜单/重置/分页等 |
| menus/groups-combined | 50项；新MSW及全部当前客户端组合，原菜单功能回归 |
| menus/groups-final | 最终375951宿主，65项；分组操作、8个客户端功能页无重复、14行布局、版本与frames=600 |
| button-style/groups-final | 最终375951宿主，24项；中文原生字体像素/位置、选中样式、记录隐藏及返回原生页 |
| menus/groups-installed | 安装后复制正式文件，65项、版本与frames=600；除探针外输入哈希与安装前完全一致 |

前四行使用17230字节的早期宿主2B6C210D…；随后仅为展开按钮补画三角箭头，最终宿主重新通过最后三行。各run.json保存准确输入，不能把早期测试写成最终文件全套重跑。MSW始终为准确E1EA候选，另通过规则1197项、豁免生产320项、多锁生产52项、激光真实存读档/开火/光束回归；证据在MSW的grouped-exemptions-20260924.md。

复现：build/build.ps1；build/test-menus.ps1 -Probe GroupProbe（可带-MSWSwf候选路径，默认三次启动）；旧宿主带-HostSwf及-SmokeOnly；最终与安装后带-SmokeOnly，安装后加-InstalledHost。中文样式运行build/test-button-style.ps1 -CandidateHost。所有运行结果落在独立RunLabel目录。

## 测试中修正的错误假设

1. 首次groups探针直接用默认路径读MSWConfig，读到undefined。默认SharedObject路径跟随所属SWF；改为通过客户端回调检查即时状态，通过同应用重启检验持久化。生产代码未因此修改。失败即时记入journal。
2. 首次旧宿主场景已通过界面检查，却错误要求新settings版本；改为按指定宿主检查0.3.1，并等待其真实心跳，重跑8项通过。
3. MSW生产探针仍硬编码1.13.0版本，首轮在行为断言前失败；更新为本轮1.13.1后重跑320项通过。

日志中invalid groups两条是探针主动注入重复/缺失键以验证原子拒绝，不是生产菜单异常。未重跑加载器三版本故障、全部激光笔/炮塔/时停战斗套件；本轮不修改加载器引导、扫描器、玩法规则或DLC支持。

## 安装、保护核对和回滚

备份work/backups/before-groups-20260924-075628/：ModLoader旧15110字节C9701A91013899E2674F29990AC6E4977A6C4678D0AE47D8C14324F97084704C；MSW旧54248字节476430BC9B1A475267D76A4C31FFC0A7A7718582498F149DD51B1C93B4C9BF9F（包含激光笔）。两文件原子替换，安装后失败路径会先成对恢复再报错，本轮复验成功未触发回滚。

build/out/groups-installation/deployment.json状态installed-and-verified，记录备份、目标、前后应用ID和所有输入哈希。安装前ID pfe-modsettings-menus-c9e3913b9bbd486b94de292a917dbd0f；安装后ID pfe-modsettings-menus-d690756b6c8941afac75171e11326f0c。已核对两个正式/备份哈希及15项保护文件均正确：三份游戏SWF、名单/版本表、其余模组包及release文本配置未改。禁用旧ModSettings仍保持0/0/0；清单总数7/3/2不变。

回滚：保存退出游戏，将上述备份的两个SWF分别恢复到ModLoader/release/ModLoaderMod.swf与MoreSkills&Weapons/release/MoreSkillsWeaponsMod.swf，重启即可。无需修改名单、版本表或配置，不能用更旧MSW备份覆盖激光笔。
