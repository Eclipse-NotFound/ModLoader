package
{
   import flash.net.SharedObject;

   /** Stores menu IDs only. Resolving an absent/delayed registration never writes a fallback. */
   public class SettingsSelection
   {
      private var storage:SharedObject;
      private var moduleId:String = "";
      private var features:Object = {};
      private var log:SettingsLog;

      public function SettingsSelection(diagnostics:SettingsLog)
      {
         log = diagnostics;
         try
         {
            storage = SharedObject.getLocal("ModSettingsMenu", "/");
            if(storage.data.moduleId is String) moduleId = storage.data.moduleId;
            if(storage.data.features != null) features = storage.data.features;
         }
         catch(e:*) { report(e); }
      }

      public function resolve(groups:Array, requestedModule:String = ""):Object
      {
         if(groups.length == 0) return null;
         var desired:String = requestedModule == "" ? moduleId : requestedModule;
         var group:Object = groups[0];
         for each(var candidate:Object in groups)
            if(candidate.id == desired) { group = candidate; break; }
         var page:Object = group.pages[0];
         for each(candidate in group.pages)
            if(candidate.modId == features["$" + group.id]) { page = candidate; break; }
         return page;
      }

      public function chooseModule(id:String):void
      {
         moduleId = id;
         save();
      }

      public function choosePage(page:Object):void
      {
         moduleId = page.moduleId;
         features["$" + moduleId] = page.modId;
         save();
      }

      private function save():void
      {
         try
         {
            if(storage == null) return;
            storage.data.moduleId = moduleId;
            storage.data.features = features;
            storage.flush();
         }
         catch(e:*) { report(e); }
      }

      private function report(e:*):void
      {
         if(log != null) log.diagSet("menuStorageError", String(e));
      }
   }
}
