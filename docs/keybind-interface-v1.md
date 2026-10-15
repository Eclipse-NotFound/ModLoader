# 菜单改键接口 v1（本轮实现合同）

当前接口已实现并通过组合验证。公共ModLoader2.4.0及FA0.3.5已按用户在改装会话的明确授权分别安装，其余六客户端仍为已验证候选；最终指纹、回读及授权边界见[state/keybind-integration-2026-10-15.md](../state/keybind-integration-2026-10-15.md)。下文“只构建候选”保留最初客户端协作范围，后续明确部署授权优先。

用户在快捷键普查主会话 01a13f40-6ca2-7872-9f9a-c1e453e80745 已要求把改键加入对应模组菜单，并允许向对应模组发送协作消息。主会话维护 ModLoader；客户端只修改自己的模组。此合同先供客户端并行接入，测试前需核对实现，不把合同当作已完成。

## 公共约定

- 服务仍为 main.getChildByName("ModSettingsCarrier").modAPI；新增 keybindVersion:int=1，不改既有 apiVersion/menuVersion。
- registerPage 新增 kind:"keybind"，其余 key/label/get/set/def/hint 与页面 navigation 契约保持。get 返回绑定对象，set 接收新的绑定对象并由客户端立即持久化；宿主不接管各模组配置。
- 绑定结构：{code:71,ctrl:true,alt:false,shift:false}；code=0 且三修饰键为 false 表示未绑定。修饰键精确匹配，额外修饰键不匹配。请保留用户旧设置，旧单键迁移时默认三个修饰键 false。
- 新页面使用 navigation:{moduleId:既有模组ID,moduleName:既有显示名,featureName:"快捷键",featureOrder:99}。注册必须支持异步晚到，服务暂不可用时保留独立默认/持久绑定逻辑；旧宿主不认识 keybind 时不注册该新页面，不能使旧功能页失效。
- api.matchesKey(pageId:String,itemKey:String,event:KeyboardEvent):Boolean：按注册项的当前 get 值精确匹配；改键捕获期间、被捕获按键释放前返回 false。只负责匹配，动作是否允许执行仍由客户端检查原版游戏/菜单/输入框等状态。
- api.isKeyDown(pageId:String,itemKey:String):Boolean：按共享物理键状态判断组合是否持续按住；改键捕获、失焦、原版界面忙碌时为 false，供举枪/维修使用。客户端仍须保留自己的动作结束/清理逻辑。
- api.isCapturingKey():Boolean：捕获期间客户端全局快捷键不得抢先动作。公共捕获监听优先级高于现有模组输入监听，包含捕获及普通阶段。
- 捕获交互由公共界面负责：Esc 取消、Delete 清除、单独修饰键继续等待；关闭/换页/失焦取消。捕获的按下及其对应松开不能落到游戏；捕获开始之前已按住的键，其松开仍放行以清理原版与客户端状态。有效新绑定立即 set/保存，按住造成的系统重复不能立即触发新动作。
- 冲突检查：裸键对照当前原版 ctr.save() 和固定保留键；所有已注册 keybind 项互查。现有默认 F10 共用不会自动改值，界面提示占用；新录入冲突不写入。恢复默认保持原本默认并显示冲突。
- 同一动作只注册一份权威 keybind 项，不能在两页重复注册同一绑定。旧菜单的提示可指向新「快捷键」页。

## 页面与动作 ID

| 模组 | pageId | itemKey 与默认 |
|---|---|---|
| MSW | msw-hotkeys | panel=F6(117)；aim=Shift+W(87) |
| Sandevistan | sandevistan-hotkeys | activate=反斜杠(220) |
| RealisticVision | realisticvision-hotkeys | debug=F10(121)；toggle=F11(122)；mode=F12(123) |
| RConnect | rconnect-hotkeys | panel=F10(121)；chat=Ctrl+Enter(13) |
| RandomRooms | randomrooms-hotkeys | explore=F1(112)；home=F2(113)；test=F3(114)；next=F4(115)；showcase=F5(116)；jump=F7(118)；debug=Shift+F3(114)；export=Shift+F5(116) |
| FirearmAttachments | firearmattachments-hotkeys | workbench=Ctrl+M(77)；bayonet=Ctrl+V(86)；bipod=Ctrl+B(66)；optic=Ctrl+O(79)；grenade=Ctrl+G(71) |
| LightAndDarkness | light-and-darkness-hotkeys | headlamp=Alt+L(76)；fixture=Alt+E(69) |

## 范围与交付

- 本轮补齐上表23项独立操作；面板内部方向键/Enter/Esc等导航不加入可改范围。不新增已经移除的F9入口，不改无独立快捷键的模组。
- 复用原版动作时读取当前 ctr.save()/keyIds，避免默认keyXML缓存导致改键后不一致；RV念力拦截应跟随原版当前念力键，这不是额外可改动作。
- 每个客户端只构建到自己的 build 候选目录，不覆盖 release 或根宿主；主会话汇总后统一验证与处理安装边界。不得覆盖其他任务未完成改动，不关闭用户游戏或写真实存档。
- 回报写入各自 state/keybind-integration-2026-10-15.md：当前基线/提交、候选路径与哈希、测试结果、未验事项，主会话会读取；不要求另一会话在没有人类独立授权的情况下发回消息。
