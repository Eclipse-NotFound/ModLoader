package
{
   import flash.utils.getDefinitionByName;
   public class SettingsRuntime
   {
      public static function world():*
      {
         var result:* = null;
         try { result = getDefinitionByName("fe.World")["w"]; } catch(e:*) {}
         return result;
      }
   }
}
