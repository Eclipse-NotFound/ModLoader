package
{
   import flash.display.Sprite;
   import flash.display.BitmapData;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.KeyboardEvent;
   import flash.utils.getDefinitionByName;
   import flash.utils.Timer;

   /** Black-box menu contract checks against the candidate SWFs in a private game. */
   public class MenuProbe extends Sprite
   {
      private static var probe:MenuProbe;
      private var main:*;
      private var w:*;
      private var api:*;
      private var timer:Timer = new Timer(50);
      private var ticks:int = 0;
      private var phase:int = 0;
      private var since:int = 0;
      private var checks:int = 0;
      private var log:String = "";
      private var scenario:String;
      private var run:String;
      private var closed:int = 0;
      private var fixtures:Array = [];

      public function MenuProbe() {}
      public static function init(m:*):void
      {
         probe = new MenuProbe(); probe.main = m;
         var parts:Array = probe.readApp("scenario.txt").split(":");
         probe.scenario = parts[0]; probe.run = parts.length > 1 ? parts[1] : "first";
         probe.timer.addEventListener("timer", probe.tick); probe.timer.start();
      }
      private function ok(value:Boolean, label:String):void
      {
         if(!value) throw new Error(label);
         checks++; log += "PASS " + label + "\n";
      }
      private function advance(value:int):void { phase = value; since = ticks; }
      private function page(id:String):*
      {
         for each(var p:Object in api.getPages()) if(p.modId == id) return p;
         return null;
      }
      private function item(id:String, key:String):*
      {
         for each(var it:Object in page(id).items) if(it.key == key) return it;
         throw new Error("Missing item " + id + "/" + key);
      }
      private function nav():* { return find(main, "ModSettingsNavigation"); }
      private function current(id:String):Boolean { return nav() != null && nav().pageId == id && api.isOpen(); }
      private function click(name:String):void
      {
         var target:* = find(main, name);
         if(target == null || !target.mouseEnabled) throw new Error("Unavailable button " + name);
         target.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true));
      }
      private function f6():void
      {
         main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, false, 0, 117));
         main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP, true, false, 0, 117));
      }
      private function fixture(id:String, count:int, moduleId:String, feature:String, order:int):void
      {
         var items:Array = [];
         for(var i:int = 0; i < count; i++)
         {
            var cell:Object = {value:true}; fixtures.push(cell);
            items.push(fixtureItem(cell, id + "/" + i));
         }
         api.registerPage(id, id, items, function():void { closed++; }, "Menu test fixture",
            {moduleId:moduleId, moduleName:moduleId, featureName:feature, featureOrder:order});
      }
      private function fixtureItem(cell:Object, key:String):Object
      {
         return {key:key, label:key, kind:"check", def:false,
            get:function():Boolean { return cell.value; }, set:function(v:*):void { cell.value = v; }};
      }
      private function tick(e:Event):void
      {
         try
         {
            ticks++;
            if(ticks % 100 == 0) write("heartbeat.txt", "ticks=" + ticks + " phase=" + phase + "\n" + log);
            if(ticks > 2400) throw new Error("timeout phase=" + phase);
            w = getDefinitionByName("fe.World")["w"];
            if(w == null) return;
            if(w.verror != null && w.verror.visible) throw new Error("game dialog: " + w.verror.txt.text);
            var carrier:* = main.getChildByName("ModSettingsCarrier"); if(carrier == null) return;
            api = carrier.modAPI;
            if(phase == 0)
            {
               if(page("sandevistan") == null || page("realisticvision") == null || page("rconnect") == null) return;
               if(scenario != "without-msw" && page("msw-exempt") == null) return;
               if(!w.allLandsLoaded) return;
               ok(countName(main,"ModSettingsCarrier") == 1, "one stable registry carrier");
               if(readApp("host-kind.txt") != "legacy")
                  ok(carrier.hostId == "ModLoader" && carrier.hostVersion == "2.2.0", "settings are hosted by ModLoader runtime");
               ok(api.getPages().length == (scenario == "without-msw" ? 3 : 7), "all legacy page IDs registered once");
               if(scenario != "legacy")
               {
                  ok(api.apiVersion == 1 && api.menuVersion == 1, "old API version and new menu capability coexist");
                  var groups:Array = api.getModules();
                  var ids:Array = []; for each(var group:Object in groups) ids.push(group.id);
                  ok(ids.join(",") == (scenario == "without-msw" ? "sandevistan,realisticvision,rconnect" :
                     "msw,sandevistan,realisticvision,rconnect"), "known modules have fixed order regardless of load order");
                  if(scenario == "all")
                  {
                     ids = []; for each(var p:Object in groups[0].pages) ids.push(p.featureName);
                     ok(ids.join(",") == "基础设置,智能武器,非致命激光枪,锁定豁免", "MSW four feature labels and order");
                  }
               }
               w.mm.active = false; w.newGame(-1, "LP", null); advance(1); return;
            }
            if(phase == 1)
            {
               if(w.gg == null || w.loc == null || ticks - since < 110) return;
               // The independent RConnect overlay starts open in a fresh test profile.
               main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, false, 0, 121));
               main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP, true, false, 0, 121));
               w.pip.onoff(5); advance(2); return;
            }
            if(phase == 2 && ticks - since > 6)
            {
               ok(countName(main, "ModSettingsButton") == 1, "exactly one settings entry");
               click("ModSettingsButton");
               if(scenario == "legacy")
               {
                  ok(!("menuVersion" in api), "old host under compatibility test");
                  ok(api.selectPage("msw-exempt") && rows().length == 18, "new MSW still registers four pages on old five-argument host");
                  f6(); ok(!api.isOpen(), "F6 falls back to old host toggle");
                  f6(); ok(api.isOpen(), "F6 old-host reopen still works");
                  finish(); return;
               }
               if(scenario == "without-msw")
               {
                  ok(current(run == "first" ? "sandevistan" : "realisticvision"), "absent MSW fallback or saved module restored");
                  ok(!api.selectModule("msw"), "absent module route returns false");
                  checkBlankFeatures();
                  api.selectPage("realisticvision");
                  screenshot("without-msw.png"); finish(); return;
               }
               if(run == "reload")
               {
                  ok(current("msw-exempt"), "missing remembered module falls back to valid module and remembered feature");
                  var so:* = getDefinitionByName("flash.net.SharedObject")["getLocal"]("ModSettingsMenu", "/");
                  ok(so.data.moduleId == "late-menu", "fallback does not overwrite persisted delayed module");
                  fixture("late-a", 1, "late-menu", "先到功能", 0);
                  advance(4); return;
               }
               if(run == "final")
               {
                  ok(current("realisticvision"), "ordinary entry restores global module across process restart");
                  f6(); ok(current("msw-exempt"), "F6 restores MSW feature separately across restart");
                  f6(); ok(!api.isOpen(), "F6 closes when already on MSW after restart");
                  finish(); return;
               }
               ok(current("msw"), "first opening defaults to MSW base");
               ok(tabIds(false).join(",") == "msw,sandevistan,realisticvision,rconnect", "four visible mod tabs");
               ok(tabIds(true).join(",") == "msw,msw-smart,msw-laser,msw-exempt", "four visible feature tabs");
               screenshot("menus-base.png");
               click("SettingsFeatureTab:msw-smart"); ok(current("msw-smart"), "smart feature tab opens");
               var cb:* = rows()[0].settingsSc;
               var old:* = rows()[0].settingsItem["get"]();
               cb.selected = !old; cb.dispatchEvent(new Event("change"));
               ok(rows()[0].settingsItem["get"]() === !old, "actual MSW checkbox callback still changes owned config");
               rows()[0].settingsItem["set"](old);
               click("SettingsFeatureTab:msw-laser"); ok(current("msw-laser"), "laser feature tab opens");
               click("SettingsFeatureTab:msw-exempt");
               ok(rows().length == 16, "exemption first content page has 16 rows");
               checkGeometry();
               for each(var exemption:Object in page("msw-exempt").items) exemption["set"](true);
               var smart:* = item("msw-smart", "smartEnabled"); old = smart["get"](); smart["set"](true);
               click("SettingsNextItems");
               ok(rows().length == 15 && current("msw-exempt"), "31 exemptions remain in one feature with second content page");
               click("SettingsReset");
               var allReset:Boolean = true;
               for each(exemption in page("msw-exempt").items) if(exemption["get"]() !== false) allReset = false;
               ok(allReset, "reset includes all 31 exemptions including hidden page");
               ok(smart["get"]() === true, "reset current feature leaves smart feature untouched"); smart["set"](old);
               screenshot("menus-exempt.png");
               click("SettingsModuleTab:realisticvision"); ok(current("realisticvision"), "module tab switches to vision");
               checkBlankFeatures(); screenshot("menus-vision.png");
               click("ModSettingsButton"); click("ModSettingsButton");
               ok(current("realisticvision"), "ordinary close/reopen restores global selection");
               f6(); ok(current("msw-exempt"), "F6 from other module selects MSW remembered feature");
               f6(); ok(!api.isOpen(), "F6 on MSW closes");
               f6(); ok(current("msw-exempt"), "F6 from closed panel restores MSW feature");
               for each(var id:String in ["sandevistan", "realisticvision", "rconnect"])
               { api.selectModule(id); ok(current(id), "legacy single-page module " + id); checkBlankFeatures(); }
               ok(item("realisticvision", "mode") != null && item("realisticvision", "enabled") != null,
                  "flat getPages lookup used by TDFC preserves vision settings");
               api.selectPage("msw-exempt");
               overflowChecks();
               fixture("late-a", 1, "late-menu", "先到功能", 0);
               fixture("late-b", 1, "late-menu", "后到功能", 1);
               api.selectPage("late-b");
               advance(3); return;
            }
            if(phase == 3 && ticks - since > (run == "smoke" ? 650 : 10)) { finish(); return; }
            if(phase == 4 && ticks - since > 4)
            {
               ok(current("late-a"), "delayed module becomes selected without another click");
               so = getDefinitionByName("flash.net.SharedObject")["getLocal"]("ModSettingsMenu", "/");
               ok(so.data.features["$late-menu"] == "late-b", "missing feature fallback retains saved feature intent");
               fixture("late-b", 1, "late-menu", "后到功能", 1);
               advance(5); return;
            }
            if(phase == 5 && ticks - since > 4)
            {
               ok(current("late-b"), "delayed preferred feature restores after registration");
               api.selectPage("realisticvision"); finish(); return;
            }
         }
         catch(err:*) { write(run + "-results.txt", log + "FAIL " + err + "\n" + err.getStackTrace()); shutdown(1); }
      }
      private function overflowChecks():void
      {
         var flat:Array = api.getPages(); var first:Object = flat[0];
         for(var i:int = 0; i < 12; i++) fixture("extra-" + i, 1, "额外模组长名称-" + i, "", 0);
         for(i = 0; i < 14; i++) fixture("feature-" + i, i == 13 ? 40 : 1, "feature-fixture", "分页功能长名称-" + i, i);
         ok(api.getPages() === flat && flat[0] === first, "group sorting leaves live flat array and page references stable");
         api.selectModule("msw");
         var visited:Object = {}; var steps:int = 0; var last:String = nav().pageId;
         while(true)
         {
            for each(var id:String in tabIds(false)) visited[id] = true;
            var next:* = find(main, "SettingsModuleNext");
            if(next == null || !next.mouseEnabled) break;
            click("SettingsModuleNext"); if(++steps > 30) throw new Error("module pager loop");
         }
         var count:int = 0; for(id in visited) count++;
         ok(steps > 0 && count == api.getModules().length, "every overflowing module tab reachable through arrows");
         ok(nav().pageId == last, "browsing module tab pages does not change active feature");
         click("SettingsModulePrevious");
         ok(find(main, "SettingsModuleTab:feature-fixture") == null, "module left arrow returns to previous tab page");
         click("SettingsModuleNext");
         click("SettingsModuleTab:feature-fixture");
         visited = {}; steps = 0;
         while(true)
         {
            for each(id in tabIds(true)) visited[id] = true;
            next = find(main, "SettingsFeatureNext");
            if(next == null || !next.mouseEnabled) break;
            click("SettingsFeatureNext"); if(++steps > 30) throw new Error("feature pager loop");
         }
         count = 0; for(id in visited) count++;
         ok(steps > 0 && count == 14, "every overflowing feature tab reachable through arrows");
         click("SettingsFeaturePrevious");
         ok(find(main, "SettingsFeatureTab:feature-13") == null, "feature left arrow returns to previous tab page");
         click("SettingsFeatureNext");
         click("SettingsFeatureTab:feature-13");
         ok(current("feature-13") && rows().length == 16, "last overflow feature selectable");
         checkGeometry(); screenshot("menus-overflow.png");
         click("SettingsNextItems"); ok(rows().length == 16, "content page two independent from tab pagination");
         click("SettingsNextItems"); ok(rows().length == 8, "content page three reachable");
         var before:int = closed; click("SettingsReset");
         var reset:Boolean = true; for each(var it:Object in page("feature-13").items) if(it["get"]()) reset = false;
         ok(reset && closed == before + 1, "whole feature reset invokes only its save callback once");
         ok(page("feature-12").items[0]["get"]() === true, "sibling feature values stay unchanged");
         var original:Object = page("feature-13");
         api.registerPage(original.modId, original.displayName, original.items, original.onPageClose, original.desc);
         ok(page("feature-13") === original && original.moduleId == "feature-fixture", "legacy five-argument refresh preserves grouping and identity");
         var revision:uint = api.revision;
         api.registerPage(original.modId, "bad", [{key:"invalid"}]);
         ok(api.revision == revision && page("feature-13") === original, "invalid registration cannot replace a working page");
         api.selectModule("msw"); ok(current("msw-exempt"), "switching away and back keeps per-module feature");
         ok(find(main, "SettingsModuleTab:msw").settingsSelected && find(main, "SettingsFeatureTab:msw-exempt").settingsSelected,
            "programmatic selection pages both tab rows back to active highlights");
      }
      private function tabIds(features:Boolean):Array
      {
         var prefix:String = features ? "SettingsFeatureTab:" : "SettingsModuleTab:"; var ids:Array = [];
         for(var i:int = 0; i < nav().numChildren; i++)
         { var child:* = nav().getChildAt(i); if(child.name.indexOf(prefix) == 0) ids.push(child.name.substr(prefix.length)); }
         return ids;
      }
      private function checkBlankFeatures():void
      {
         var blank:Boolean = true;
         for(var i:int = 0; i < nav().numChildren; i++)
         { var child:* = nav().getChildAt(i); if(child.y >= 30 && child.y < 60) blank = false; }
         ok(blank, "unclassified module reserves an empty second row");
      }
      private function checkGeometry():void
      {
         var valid:Boolean = true;
         for each(var row:* in rows())
         {
            if(row.settingsSc != null && "drawNow" in row.settingsSc) row.settingsSc.drawNow();
            if(row.y < 160 || row.y + row.height > 610)
            { valid = false; log += "GEOMETRY y=" + row.y + " height=" + row.height + "\n"; }
         }
         ok(valid, "settings rows fit below both tab rows and above panel bottom");
      }
      private function find(o:*, name:String):*
      {
         if(o == null) return null; if(o.name == name) return o;
         if("numChildren" in o) for(var i:int = 0; i < o.numChildren; i++)
         { var result:* = find(o.getChildAt(i), name); if(result != null) return result; }
         return null;
      }
      private function countName(o:*, name:String):int
      {
         if(o == null) return 0; var n:int = o.name == name ? 1 : 0;
         if("numChildren" in o) for(var i:int = 0; i < o.numChildren; i++) n += countName(o.getChildAt(i), name);
         return n;
      }
      private function collect(o:*, a:Array):void
      {
         if(o == null || !o.visible) return; if("settingsItem" in o) a.push(o);
         if("numChildren" in o) for(var i:int = 0; i < o.numChildren; i++) collect(o.getChildAt(i), a);
      }
      private function rows():Array { var a:Array = []; collect(main, a); return a; }
      private function fileText(file:*):String
      {
         if(!file.exists) return "";
         var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class; var s:* = new S();
         s.open(file, "read"); var value:String = s.readUTFBytes(s.bytesAvailable); s.close(); return value;
      }
      private function readApp(path:String):String { return fileText(getDefinitionByName("flash.filesystem.File")["applicationDirectory"].resolvePath(path)); }
      private function write(name:String, text:String):void
      {
         var F:Class = getDefinitionByName("flash.filesystem.File") as Class; var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var s:* = new S(); s.open(F["applicationStorageDirectory"].resolvePath(name), "write"); s.writeUTFBytes(text); s.close();
      }
      private function screenshot(name:String):void
      {
         for each(var row:* in rows()) if(row.settingsSc != null && "drawNow" in row.settingsSc) row.settingsSc.drawNow();
         var stage:* = main.stage; var bitmap:BitmapData = new BitmapData(stage.stageWidth, stage.stageHeight, false, 0); bitmap.draw(stage);
         var E:Class = getDefinitionByName("flash.display.PNGEncoderOptions") as Class;
         var bytes:* = Object(bitmap)["encode"](bitmap.rect, new E());
         var F:Class = getDefinitionByName("flash.filesystem.File") as Class; var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var s:* = new S(); s.open(F["applicationStorageDirectory"].resolvePath(name), "write"); s.writeBytes(bytes); s.close(); bitmap.dispose();
      }
      private function finish():void
      {
         var text:String = fileText(getDefinitionByName("flash.filesystem.File")["applicationStorageDirectory"].resolvePath("ModSettings.log"));
         ok(text.indexOf("lastErr=") < 0 && text.indexOf("menuStorageError=") < 0, "no UI or menu persistence error");
         if(run == "smoke")
         {
            ok(text.indexOf("v0.3.1 loaded") >= 0, "installed host reports new version");
            var frames:int = 0; var re:RegExp = /frames=(\d+)/g; var match:Object;
            while((match = re.exec(text)) != null) frames = Math.max(frames, int(match[1]));
            ok(frames >= 600, "installed host frame heartbeat continues after menu operations");
         }
         api.closeAll(); write(run + "-results.txt", log + "PASS " + checks + " assertions\n"); shutdown(0);
      }
      private function shutdown(code:int):void { timer.stop(); getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(code); }
   }
}
