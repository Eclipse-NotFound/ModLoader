package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;

   /** Isolated one-shot synthetic long frame. Never installed in the player's game. */
   public class RecorderFaultMod extends Sprite
   {
      private static var main:*, beginning:int = 0;
      public static function init(m:*):void
      {
         var app:* = getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"];
         var xml:XML = app.applicationDescriptor, ns:Namespace = xml.namespace();
         if(String(xml.ns::id).indexOf("pfe-agentdebug-") != 0) return;
         main = m; main.stage.addEventListener(Event.ENTER_FRAME, tick);
      }
      private static function tick(e:Event):void
      {
         var w:* = getDefinitionByName("fe.World")["w"];
         if(w == null || w.gg == null || w.loc == null || w.allStat != 1) return;
         if(beginning == 0) beginning = getTimer();
         if(getTimer() - beginning < 7000) return;
         main.stage.removeEventListener(Event.ENTER_FRAME, tick);
         var at:int = getTimer();
         while(getTimer() - at < 180) {}
         var host:* = main.getChildByName("ModSettingsCarrier");
         if(host != null) host.recorderFault = {startTimerMs:at, endTimerMs:getTimer(),
            land:w.game.curLandId, loc:w.loc.id, x:w.gg.X, y:w.gg.Y};
      }
   }
}
