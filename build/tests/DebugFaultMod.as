package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.utils.getTimer;
   import flash.utils.getDefinitionByName;
   /** Deliberately bad fixture: test copies only. Never installed in the real mods folder. */
   public class DebugFaultMod extends Sprite
   {
      public function DebugFaultMod() {}
      public static function init(main:*):void
      {
         var N:Class=getDefinitionByName("flash.desktop.NativeApplication") as Class;
         var xml:XML=N["nativeApplication"].applicationDescriptor;
         var ns:Namespace=xml.namespace();
         if(String(xml.ns::id).indexOf("pfe-agentdebug-") != 0) return;
         var overlay:Sprite=new Sprite(); overlay.name="DebugFaultMagentaOverlay";
         overlay.graphics.beginFill(0xff00ff,0.8);overlay.graphics.drawRect(40,40,220,140);overlay.graphics.endFill();
         main.stage.addChild(overlay);
         main.stage.addEventListener(Event.ENTER_FRAME,function(e:Event):void {
            var start:int=getTimer();while(getTimer()-start<85) {}
         });
      }
   }
}
