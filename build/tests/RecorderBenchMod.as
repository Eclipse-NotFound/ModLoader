package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;

   /** Two ABBA blocks in one unchanged menu/process; first five seconds discarded. */
   public class RecorderBenchMod extends Sprite
   {
      private static var main:*, host:*, api:*, w:*;
      private static var pattern:Array = [false,true,true,false,false,true,true,false];
      private static var index:int = -1, since:int, previous:int;
      private static var frames:Array = [], blocks:Array = [];
      public static function init(m:*):void
      {
         var app:* = getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"];
         var xml:XML = app.applicationDescriptor, ns:Namespace = xml.namespace();
         if(String(xml.ns::id).indexOf("pfe-agentdebug-") != 0) return;
         main = m; main.stage.addEventListener(Event.ENTER_FRAME, tick);
      }
      private static function tick(event:Event):void
      {
         try
         {
            var now:int = getTimer();
            if(index < 0)
            {
               w = getDefinitionByName("fe.World")["w"];
               host = main.getChildByName("ModSettingsCarrier");
               if(host == null || w == null || !w.mm.loaded || !w.allLandsLoaded || !w.textLoaded || w.musicLoaded < w.musicKol) return;
               api = host.frameRecorder;
               next(now); return;
            }
            if(!w.mm.active || main.stage.frameRate != 30) throw new Error("menu/rate changed");
            if(now - since >= 5000 && previous - since >= 5000) frames.push(now - previous);
            previous = now;
            if(now - since < 25000) return;
            blocks.push({enabled:pattern[index], framesMs:frames, status:api.status()});
            next(now);
         }
         catch(error:*)
         {
            if(host != null) host.recorderBenchmark = {done:false,error:String(error),blocks:blocks};
            main.stage.removeEventListener(Event.ENTER_FRAME, tick);
         }
      }
      private static function next(now:int):void
      {
         index++; frames = []; since = previous = now;
         if(index == pattern.length)
         {
            if(!api.setSampling(true)) throw new Error("resume after comparison failed");
            host.recorderBenchmark = {done:true,blocks:blocks, afterComparison:api.status()};
            main.stage.removeEventListener(Event.ENTER_FRAME, tick); return;
         }
         if(!api.setSampling(pattern[index])) throw new Error("sampling toggle failed: " + JSON.stringify(api.status()));
      }
   }
}
