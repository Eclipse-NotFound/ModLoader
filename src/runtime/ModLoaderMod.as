package
{
   import flash.display.Sprite;

   /** Runtime services shipped with ModLoader; MainFE still owns SWF loading. */
   public class ModLoaderMod extends Sprite
   {
      public static const VERSION:String = "2.3.0";
      private static var initialized:Boolean = false;

      public function ModLoaderMod() {}

      public static function init(main:*):void
      {
         if(initialized || main == null) return;
         SettingsHost.init(main);
         initialized = true;
         new SettingsLog().write("ModLoader runtime v" + VERSION + " loaded; settings v" + SettingsHost.VERSION);
      }
   }
}
