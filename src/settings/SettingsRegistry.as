package
{
   /** Callback-only registry: storage and gameplay always belong to the client. */
   public class SettingsRegistry
   {
      public const apiVersion:int = 1;
      public const menuVersion:int = 1;
      private var entries:Array = [];
      private var modules:Array = [];
      private var moduleRevision:int = -1;
      private var serial:uint = 0;
      private var log:SettingsLog;
      private var view:Object;

      public function SettingsRegistry(diagnostics:SettingsLog = null)
      {
         log = diagnostics;
      }

      public function get revision():uint { return serial; }

      internal function attachView(callbacks:Object):void { view = callbacks; }
      /** Optional UI routing for a client's existing shortcut. No global key is claimed. */
      public function togglePage(modId:String = ""):Boolean
      {
         return view != null && view.toggle(modId);
      }
      public function selectPage(modId:String):Boolean
      {
         return view != null && view.select(modId);
      }
      public function isOpen():Boolean { return view != null && view.isOpen(); }
      public function toggleModule(moduleId:String):Boolean
      {
         return view != null && view.toggleModule(moduleId);
      }
      public function selectModule(moduleId:String):Boolean
      {
         return view != null && view.selectModule(moduleId);
      }

      public function registerPage(modId:String, displayName:String, items:Array,
                                   onPageClose:Function = null, desc:String = "", navigation:Object = null):void
      {
         if(modId == null || modId.length == 0 || items == null) return;
         // Validate before replacing an existing, working page; never invoke callbacks here.
         var keys:Object = {};
         for each(var it:Object in items)
         {
            if(it == null || it.key == null || !(it["get"] is Function) || !(it["set"] is Function)
               || (it.kind != "check" && it.kind != "slider") || keys["$" + it.key])
            { report("invalid item in " + modId); return; }
            if(it.kind == "slider" && (!isFinite(Number(it.min)) || !isFinite(Number(it.max))
               || !isFinite(Number(it.step)) || Number(it.step) <= 0 || Number(it.max) < Number(it.min)))
            { report("invalid slider in " + modId); return; }
            keys["$" + it.key] = true;
         }
         var page:Object = null;
         for each(var p:Object in entries) if(p.modId == modId) { page = p; break; }
         if(page == null) { page = {modId:modId}; entries.push(page); }
         page.displayName = displayName == null || displayName == "" ? modId : displayName;
         page.items = items;
         page.onPageClose = onPageClose;
         page.desc = desc;
         // modId remains the legacy page ID. Grouping is additional metadata only.
         if(navigation != null || page.moduleId == null)
         {
            page.moduleId = navigation != null && navigation.moduleId ? String(navigation.moduleId) : modId;
            page.moduleName = navigation != null && navigation.moduleName ? String(navigation.moduleName) : page.displayName;
            page.featureName = navigation != null && navigation.featureName ? String(navigation.featureName) : "";
            page.featureOrder = navigation != null && isFinite(Number(navigation.featureOrder)) ? Number(navigation.featureOrder) : entries.indexOf(page);
         }
         serial++;
      }

      // Live view retained for the existing callback contract; clients treat it as read-only.
      public function getPages():Array { return entries; }

      /** Ordered presentation view; never reorders or replaces the flat client view. */
      public function getModules():Array
      {
         if(moduleRevision == int(serial)) return modules;
         modules = [];
         var byId:Object = {};
         var knownIds:Array = ["msw", "sandevistan", "realisticvision", "rconnect"];
         var knownNames:Array = ["MSW", "斯安维斯坦", "视野系统", "RConnect"];
         for each(var page:Object in entries)
         {
            var group:Object = byId["$" + page.moduleId];
            if(group == null)
            {
               var rank:int = knownIds.indexOf(page.moduleId);
               group = {id:page.moduleId, name:rank < 0 ? page.moduleName : knownNames[rank],
                  order:rank < 0 ? 4 + modules.length : rank, pages:[]};
               byId["$" + page.moduleId] = group;
               modules.push(group);
            }
            group.pages.push(page);
         }
         modules.sortOn("order", Array.NUMERIC);
         for each(group in modules) group.pages.sortOn("featureOrder", Array.NUMERIC);
         moduleRevision = int(serial);
         return modules;
      }

      public function closeAll():void
      {
         // Snapshot callbacks so a client registering during close cannot extend this pass.
         var callbacks:Array = [];
         for each(var page:Object in entries) callbacks.push({id:page.modId, fn:page.onPageClose});
         for each(var cb:Object in callbacks) invoke(cb.fn, "close:" + cb.id);
      }

      public function resetPage(index:int):Object
      {
         var result:Object = {applied:0, failed:0};
         if(index < 0 || index >= entries.length) return result;
         var page:Object = entries[index];
         var items:Array = page.items.concat();
         for each(var it:Object in items)
         {
            if(it == null || it["def"] === undefined || it["def"] === null) continue;
            try { it["set"](it["def"]); result.applied++; }
            catch(e:*) { result.failed++; report("reset:" + page.modId + "/" + it.key + ":" + e); }
         }
         invoke(page.onPageClose, "reset-close:" + page.modId);
         return result;
      }

      private function invoke(fn:*, context:String):void
      {
         try { if(fn != null) fn(); }
         catch(e:*) { report(context + ":" + e); }
      }

      private function report(message:String):void
      {
         if(log != null) log.diagSet("callbackError", message);
      }
   }
}
