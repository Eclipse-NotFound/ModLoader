# ModLoader 内置设置接口

运行模块 v2.2.0，设置服务 v0.3.1；设置实现由本项目 src/settings 独立维护，来源为 ModSettings v0.3.1。构建不依赖旧项目。配置值、保存与玩法始终由客户端自持。

设置只在 1.02 启用。载体仍为 World.w.main.getChildByName("ModSettingsCarrier").modAPI，避免客户端同步改名；载体额外提供 hostId="ModLoader" 和 hostVersion="2.2.0" 供诊断。日志仍为 ModSettings.log。

## 菜单行为

第一行模组、第二行功能；无分类时第二行留空。固定顺序 MSW→斯安维斯坦→视野系统→RConnect，未安装的不显示，新模组追加。MSW 下为基础设置、智能武器、非致命激光枪、锁定豁免。两行标签分别用箭头分页，控件独立分页，每页最多16项。

普通“模组”按钮恢复全局上次位置；Pip 内 F6 进入 MSW 上次功能，在 MSW 时收起；游戏内原 F6 浮层不变。ModSettingsMenu（根路径 /）只保存菜单 ID，沿用旧版存储。记忆的模组或功能尚未登记时显示有效替代但不覆盖原意图，晚到注册仍可恢复，显式选择另一目标才更新记忆。

如出现旧 MSWModAPICarrier，设置宿主保留登记簿、撤下自己界面，由旧宿主管理原入口。没有发布旧名称的别名，也不自行占用热键。独立 ModSettings 与 ModLoader 两个设置宿主不应同时启用，通过 supported-mods.txt 中旧入口0/0/0避免竞争。

## 接入接口 v1

客户端接入范例：

```actionscript
var carrier:* = world.main.getChildByName("ModSettingsCarrier");
if (carrier != null) {
    var api:* = carrier["modAPI"];
    api.registerPage("myMod", "我的模组", [
        {key:"enabled", label:"启用", kind:"check", def:true,
         hint:"开关说明",
         get:function():* { return config.enabled; },
         set:function(v:*):void { config.enabled = Boolean(v); save(); }},
        {key:"strength", label:"强度", kind:"slider", min:0, max:100,
         step:1, def:50, suffix:"%", hint:"调整后实时生效",
         get:function():* { return config.strength; },
         set:function(v:*):void { config.strength = Number(v); }}
    ], function():void { save(); }, "这个模组的说明");
}
```

- 找不到载体时稍后重试。读取父级显示对象，避免通过 `getDefinitionByName` 查找兄弟加载域中的模组类。
- `registerPage(modId:String, displayName:String, items:Array, onPageClose:Function = null, desc:String = "", navigation:Object = null):void`。`modId` 保留旧含义，即页面 ID。同名注册更新原页，注册次序不变；打开的界面会自动刷新。旧五参数调用原样有效。
- `getPages():Array` 返回动态页面对象数组（`modId/displayName/items/onPageClose/desc`），供诊断读取。它是活引用，客户端按只读使用；更新请重新注册。
- `apiVersion:int = 1`，`revision:uint` 在成功注册或更新时递增。无效输入被忽略并写日志，不覆盖已有有效页。
- `togglePage(modId:String=""):Boolean`、`selectPage(modId:String):Boolean`、`isOpen():Boolean` 保留旧路由。前两项要求哔哔小马已打开，受按键绑定对话框保护。`togglePage` 在面板展开时收起；`selectPage` 按旧页面 ID 进入所属模组/功能。
- `menuVersion:int = 1` 表示支持层级扩展。第六参 `{moduleId:"myMod", moduleName:"我的模组", featureName:"智能功能", featureOrder:0}` 指定所属模组、功能名及顺序。不提供时按独立无分类模组显示；已有元数据的页面被旧五参数调用刷新时保留层级。固定四模组的显示名与顺序由中枢统一。
- `getModules():Array` 是按显示顺序排列的分组视图（`id/name/pages`），页面仍为原对象；`getPages()` 始终保持平面原序，兼容 TDFC 等只读消费者。两种视图均按只读使用。
- `selectModule(moduleId:String):Boolean` 进入该模组记忆的功能；`toggleModule` 在同一模组已展开时关闭，其余情况进入该模组。MSW F6 优先用此接口；旧宿主未声明 `menuVersion` 时仍走旧五参数登记和 `togglePage`。
- 每项需要唯一 `key`、显示名 `label`、`kind`、`get/set` 回调。控件支持 `check` 和 `slider`；后者必须给出有限的 `min/max/step`，`max >= min`、`step > 0`。
- 控件直接调用 setter；开关是否立即保存由客户端决定。滑块变化不触发 `onPageClose`；收起整块面板、离开页面或为旧宿主让位时，依次调用所有页面的关闭回调。切换模组或设置项分段不保存。
- “恢复默认”处理当前功能的所有带 `def` 的项目（含未显示的分段），然后调用该页关闭回调；无分类时处理该模组整页。不会重置同模组的其他功能。缺少 `def` 的项目保留原值；某项报错不会阻止后续项目，界面显示失败数量。
- 客户端回调自行约束数值和保存失败；单个回调异常不会中断其他页保存。宿主日志在应用存储目录 `ModSettings.log`，超过 256 KiB 后从新日志开始。
