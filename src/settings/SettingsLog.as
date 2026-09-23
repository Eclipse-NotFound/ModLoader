package
{
   import flash.utils.getDefinitionByName;
   public class SettingsLog
   {
      public var diag:Object = {};
      public function SettingsLog() {}
      public function diagSet(key:String, value:*):void
      {
         if(diag[key] === value) return;
         diag[key] = value;
         write(key + "=" + value);
      }
      public function diagAdd(key:String):void
      {
         diagSet(key, int(diag[key]) + 1);
      }
      public function write(message:String):void
      {
         var stream:* = null;
         try
         {
            var F:Class = getDefinitionByName("flash.filesystem.File") as Class;
            var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
            var file:* = F["applicationStorageDirectory"].resolvePath("ModSettings.log");
            // Bound diagnostics; never touch a client's configuration or saved game.
            if(file.exists && file.size > 262144) file.deleteFile();
            stream = new S(); stream.open(file, "append");
            stream.writeUTFBytes("[ModSettings] " + message + "\n");
         }
         catch(e:*) { trace("[ModSettings] " + message); }
         finally { try { if(stream != null) stream.close(); } catch(ignored:*) {} }
      }
   }
}
