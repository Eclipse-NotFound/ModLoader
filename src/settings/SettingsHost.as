package
{
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;

   public class SettingsHost extends Sprite
   {
      public static const VERSION:String = "0.4.0";
      private static var instance:SettingsHost;
      private var main:*;
      private var carrier:MovieClip;
      private var settings:SettingsRegistry;
      private var diagnostics:SettingsLog;
      private var panel:SettingsPipTab;
      private var selection:SettingsSelection;
      private var frames:uint = 0;

      public function SettingsHost() {}

      public static function init(main:*):void
      {
         if(instance != null || main == null) return;
         instance = new SettingsHost();
         instance.main = main;
         instance.diagnostics = new SettingsLog();
         instance.diagnostics.write("v" + VERSION + " loaded");
         instance.settings = new SettingsRegistry(instance.diagnostics);
         instance.selection = new SettingsSelection(instance.diagnostics);
         instance.settings.attachView({
            toggle:function(id:String):Boolean {
               return instance.panel != null && instance.panel.togglePage(SettingsRuntime.world(), id);
            },
            select:function(id:String):Boolean {
               return instance.panel != null && instance.panel.selectPage(SettingsRuntime.world(), id);
            },
            toggleModule:function(id:String):Boolean {
               return instance.panel != null && instance.panel.toggleModule(SettingsRuntime.world(), id);
            },
            selectModule:function(id:String):Boolean {
               return instance.panel != null && instance.panel.selectModule(SettingsRuntime.world(), id);
            },
            isOpen:function():Boolean { return instance.panel != null && instance.panel.isActive(); }
         });
         main.addEventListener(Event.ENTER_FRAME, instance.tick);
      }

      private function tick(e:Event):void
      {
         try
         {
            if(carrier == null)
            {
               // Do not steal the name from an already loaded independent host.
               if(main.getChildByName("ModSettingsCarrier") != null)
               { diagnostics.diagSet("host", "name already occupied"); return; }
               carrier = new MovieClip();
               carrier.name = "ModSettingsCarrier";
               carrier["modAPI"] = settings;
               carrier["hostId"] = "ModLoader";
               carrier["hostVersion"] = ModLoaderMod.VERSION;
               carrier.visible = false;
               main.addChild(carrier);
               diagnostics.diagSet("host", "published");
            }
            var w:* = SettingsRuntime.world();
            if(w == null) return;
            // Stage 1 compatibility: old host retains its entire interface and UI.
            if(main.getChildByName("MSWModAPICarrier") != null)
            {
               if(panel != null) { panel.dispose(w); panel = null; }
               diagnostics.diagSet("ui", "yielded-to-legacy");
            }
            else
            {
               if(panel == null) panel = new SettingsPipTab(settings, diagnostics, selection);
               diagnostics.diagSet("ui", "independent");
               panel.update(w);
            }
            frames++;
            if(frames % 600 == 0) diagnostics.diagSet("frames", frames);
         }
         catch(err:*) { diagnostics.diagSet("lastErr", "tick:" + err); }
      }
   }
}
