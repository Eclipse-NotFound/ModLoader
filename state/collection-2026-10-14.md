# 2026-10-14 除 RModifier 外的模组合集

用户要求把全部模组最新稳定版本整理为方便分发的压缩包，明确排除 RModifier。本轮按**已完成验证部署的原字节**取包；保留 RConnect 的 dev/预发布身份，不提升稳定性声明。未重新编译当前在途源码，也未部署本机正式文件或对外上传。

## 交付

- `build/out/Remains-AllMods-NoRModifier-2026-10-14.zip`，10,213,495字节，SHA256 `3f89d6c5ecf3452dd863ef2790dce75df221b2c2bd3818d00e7ae5845c6a1d6d`；同目录有外部校验文件。
- 35个ZIP文件，其中28个安装文件；十个运行组件（九个玩法＋ModLoader设置/加载组件）、1.02配套宿主、场景数据、扫描器、A版合作启动器、说明、Install/Restore和校验清单。
- ModLoader2.3.0/settings0.4.0、Sandevistan1.145、TDFC0.6.4、RandomRooms13.2含10-03语言；MSW1.16.0-flashbang；RConnect0.2.22-dev A；ContinuousScene0.3.0/RV0.30.4-scene/WallBlend0.4.2成组冻结；FirearmAttachments0.1.0。
- 不含RModifier、M51/B接口候选、个人DLC创作工程、旧ModSettings、配置/存档/IP、音乐、开发工具、探针或旧备份。RandomRooms的可选编辑器不属于游戏运行依赖，未收入。
- 合集限定Windows/Remains1.02；分发用清单和扫描器版本表均将十个组件设为1/0/0，旧设置及RModifier设0/0/0。未修改本机两表。

## 安装与恢复

完整解压后运行Install.bat，输入含pfe.swf的游戏目录；支持已知1.02原版/现有loader/已部署大场景指纹。校验包后备份到目标`.modpack-backups/唯一时间戳/`再定向安装，保留已有配置。不改变application.xml、DLC或pfe60，不写玩家存档。

保存退出后Restore.bat输入对应备份目录，按receipt.json还原旧文件并移除本次新增文件；安装后又有修改则停止，避免覆盖后续版本。新装不复制本机RConnect含autoFollow/freezeAI的测试配置，使用SWF默认值。Sandy也使用内置默认，不复制带旧F9字段的过时模板；音乐另有指南。

## 验证与边界

证据根：`build/out/collection-20261014-231927/`，原输入指纹`frozen-inputs.json`，结果`final-verification.json`。

1. 候选ZIP实际解压后，运行**包内安装器**升级临时旧宿主，核对27个替换/新增文件、已有配置保留、自动备份、回退旧宿主和移除新增模组；未知宿主拒绝且不写入。
2. **包内扫描器**在临时目录实跑：十项1.02、零DLC、禁用旧设置/RModifier。
3. 解压的准确生产字节在独立AIR身份`pfe-modsettings-distribution-20261014232737616`正常原生启动50秒，十项requested/ok、两禁用项无请求、无loader错误；版本、设置600帧、视野/场景/墙面心跳、新鲜日志和无LootEditor日志通过。只结束该脚本自有PID，不操作玩家进程/正式存档。
4. **最终82项全部通过**；最终ZIP CRC、35项逐字节回读、SHA256清单、打包前后原输入未变均通过。

历史同字节功能验证沿用各项目记录：10-03语言4432项，MSW闪光弹133/激光199与900帧，A22原38组4760项，大场景48＋墙面43＋视野42＋安装后原生15项，枪械改装正式72项。本次只复验整合加载/安装回退，不冒称完整联机或全玩法混装认证。RConnect仍是预发布；大场景是测试地图，首次约13.5秒/步行中位55ms/峰值约3.1GB，未稳定30帧。

原失败保留：`extracted/verification`沙箱内独立AppData无法写；`verification-native`旧通用验证器误要求Sandy默认关闭的日志；`verification-final`将空`preferenceError`字段名匹配成实际ERROR。最终改为原生新鲜runID＋逐组件requested/ok、明确错误词/failed=true，不开启诊断配置、不改生产字节；`verification-approved/result.json`为最终绿灯。

## 工具与发布检查

- `tools/package_collection.py`冻结/整理；`tools/verify_collection.ps1 -Stage <解压目录> -Attempt verification-approved`验证；`tools/finalize_collection.py <本轮输出目录>`复核后生成ZIP。
- `tools/collection-install.ps1`是包内Install.ps1的正源。工具有明确输出与指纹拒绝，已存在产物不覆盖。
- 发布门禁：复用原构建/版本/功能实证；新增包安装、回退、原生启动和ZIP回读；此次不部署，线上备份/覆盖条目不适用。运行版本未变，不新增运行时changelog版本行。记忆/日志/工具提交ModLoader本地仓库，不推送。

参考经验已核对KB-000069（前后输入与实际包指纹）；未进入其RModifier来源目录。经验检索部分原区来源不可读，不据此断言不存在其它经验。
