package
{
   /** Presentation metadata over the existing flat callback list. Owns no settings. */
   public class SettingsGroups
   {
      public static function normalize(specs:*, items:Array):Array
      {
         if(!(specs is Array)) throw new Error("groups must be an array");
         var byKey:Object = {}, used:Object = {}, ids:Object = {}, result:Array = [];
         for each(var item:Object in items) byKey["$" + item.key] = item;
         for each(var spec:Object in specs)
         {
            if(spec == null || !(spec.id is String) || spec.id == "" || ids["$" + spec.id]
               || !(spec.keys is Array) || spec.keys.length == 0
               || (spec.setAll != null && !(spec.setAll is Function))) throw new Error("invalid group");
            var group:Object = {id:spec.id, label:spec.label == null ? spec.id : String(spec.label),
               keys:[], items:[], itemLabels:{}, setAll:spec.setAll,
               offLabel:spec.offLabel == null ? "未启用" : String(spec.offLabel),
               mixedLabel:spec.mixedLabel == null ? "部分启用" : String(spec.mixedLabel),
               onLabel:spec.onLabel == null ? "全部启用" : String(spec.onLabel)};
            for each(var key:* in spec.keys)
            {
               item = byKey["$" + key];
               if(!(key is String) || item == null || used["$" + key]
                  || (group.setAll != null && item.kind != "check")) throw new Error("invalid group item: " + key);
               used["$" + key] = true; group.keys.push(key); group.items.push(item);
               if(spec.itemLabels != null && spec.itemLabels[key] is String) group.itemLabels[key] = spec.itemLabels[key];
            }
            ids["$" + spec.id] = true; result.push(group);
         }
         return result;
      }

      /** Group position follows its first flat item; members follow the declared keys. */
      public static function project(page:Object, expanded:String):Array
      {
         var byKey:Object = {}, shown:Object = {}, result:Array = [];
         for each(var group:Object in page.groups)
            for each(var key:String in group.keys) byKey["$" + key] = group;
         for each(var item:Object in page.items)
         {
            group = byKey["$" + item.key];
            if(group == null) { result.push({item:item}); continue; }
            if(shown["$" + group.id]) continue;
            shown["$" + group.id] = true; result.push({group:group});
            if(group.id == expanded)
               for each(var child:Object in group.items)
                  result.push({item:child, nested:true, label:group.itemLabels[child.key]});
         }
         return result;
      }

      public static function state(group:Object):Object
      {
         var selected:int = 0, failed:int = 0;
         for each(var item:Object in group.items)
         {
            try { if(item["get"]() === true) selected++; }
            catch(e:*) { failed++; }
         }
         var total:int = group.items.length;
         return {selected:selected, total:total, failed:failed,
            label:failed > 0 ? "读取失败" : selected == 0 ? group.offLabel : selected == total ? group.onLabel : group.mixedLabel};
      }
   }
}
