package
{
   import flash.display.Sprite;
   /** Deliberately broken test fixture; never published or included in runtime builds. */
   public class ModLoaderMod extends Sprite
   {
      public function ModLoaderMod() {}
      public static function init(main:*):void { throw new Error("Expected isolated init failure"); }
   }
}
