# ModLoader 内置设置接口

运行模块 v2.3.0，设置服务 v0.4.0；设置实现由本项目 src/settings 独立维护，来源为 ModSettings v0.3.1。构建不依赖旧项目。配置值、保存与玩法始终由客户端自持。

设置只在 1.02 启用。载体仍为 World.w.main.getChildByName("ModSettingsCarrier").modAPI，避免客户端同步改名；载体额外提供 hostId="ModLoader" 和 hostVersion="2.3.0" 供诊断。日志仍为 ModSettings.log。

## 菜单行为

第一行模组、第二行功能；无分类时第二行留空。固定顺序 MSW→斯安维斯坦→视野系统→RConnect，未安装的不显示，新模组追加。MSW当前下属功能含基础设置、智能武器、非致命激光枪、锁定豁免、激光笔，由客户端登记。两行标签分别用箭头分页，控件独立分页，每页最多16行。

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

## 可展开分组接口 v1

`groupVersion:int = 1` 表示支持可展开分组。`registerPage`第六个参数新增可选`groups:Array`，与原moduleId/featureName等字段并存；原调用签名、apiVersion和menuVersion均保持。`items`始终是原来完整的平面列表，getPages只读消费者、旧宿主和客户端快捷面板不需要处理新kind。

```actionscript
var navigation:Object = {moduleId:"myMod", moduleName:"我的模组", featureName:"目标设置"};
if ("groupVersion" in api && api.groupVersion >= 1) {
    navigation.groups = [{
        id:"animals", label:"生物", keys:["rat", "fish"],
        itemLabels:{rat:"老鼠", fish:"鱼类"},
        offLabel:"未豁免", mixedLabel:"部分豁免", onLabel:"全部豁免",
        setAll:function(value:Boolean):void {
            config.rat = value; config.fish = value; save();
        }
    }];
}
api.registerPage("my-targets", "目标设置", flatItems, save, "说明", navigation);
```

- 每组需要唯一非空`id`和非空`keys`；key必须引用本页既有项，同一项不能重复归属。`label`默认为id；`itemLabels`可覆盖展开时的短标签，不改原平面item.label。
- 组的位置取其首个成员在平面列表中的位置，组内顺序按keys。未分组的项继续按原平面顺序显示。仅支持一层分组；开关和滑杆均能作为成员。
- 不提供`setAll`时只有展开/收起能力，可包含滑杆；提供时必须全部为check项。大类按钮按getter统计全不选/部分/全选及数量；前两者调用setAll(true)，全选调用setAll(false)。默认状态词为未启用/部分启用/全部启用，可如例覆盖。
- 宿主只调用一次setAll；批量修改、数值约束、保存由注册方负责。操作后重新读取实际值；回调抛错写日志，部分成功如实显示，getter抛错则显示读取失败并禁止批量操作。
- 同一页最多展开一个组；展开按钮不调用设置setter。第一次全部收起，关闭/切换/重启后恢复，显式全部收起也持久化。位置仍在ModSettingsMenu（/）的expandedGroups中，按页面/组ID保存；临时缺席不覆写原意图。
- 16行限制包含组标题，超出后分页，所有小项可达。恢复默认遍历完整平面items，包含收起或不可见成员，不改变展开位置。
- 显式`groups:[]`清除分组。省略groups保留已有分组，重新绑定到本次items；若旧刷新删掉其成员，则记录诊断并回退为可用的平面页。显式无效分组会原子拒绝本次登记，保留此前有效页面。
- 当前MSW锁定豁免用5组31项接入，最大展开14行；组操作在MSW内一次修改并保存，F6仍读同一平面31项，既有选择与玩法语义不变。
