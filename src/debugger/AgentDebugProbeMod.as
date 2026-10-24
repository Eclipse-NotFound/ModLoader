package
{
   import flash.display.Sprite;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.events.Event;
   import flash.net.SharedObject;
   import flash.utils.Timer;
   import flash.utils.getTimer;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import flash.system.System;

   /** Passive frame delivery sampler. Only runs in a debugger-owned AIR application. */
   public class AgentDebugProbeMod extends Sprite
   {
      private static var probe:AgentDebugProbeMod;
      private var main:*, w:*, plan:Object;
      private var timer:Timer = new Timer(50);
      private var phase:String = "boot", since:int, began:int, previous:int;
      private var frames:Array = [], activity:Array = [];
      private var firstScene:Object, memoryStart:Number, targetRate:Number;
      private var rateChanged:Boolean = false, nodes:Array = [], truncated:Boolean = false;
      private var lastBootReport:int = 0;
      public function AgentDebugProbeMod() {}
      public static function init(m:*):void
      {
         var F:Class = getDefinitionByName("flash.filesystem.File") as Class;
         var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var N:Class = getDefinitionByName("flash.desktop.NativeApplication") as Class;
         var app:* = N["nativeApplication"], xml:XML = app.applicationDescriptor;
         var ns:Namespace = xml.namespace();
         var id:String = String(xml.ns::id);
         if(id.indexOf("pfe-agentdebug-") != 0) return;
         var f:* = F["applicationDirectory"].resolvePath("agent-debug-plan.json");
         if(!f.exists) return;
         var s:* = new S(); s.open(f,"read");
         var p:Object = JSON.parse(s.readUTFBytes(s.bytesAvailable)); s.close();
         if(p.appId != id || p.protocol != 1) return;
         probe = new AgentDebugProbeMod(); probe.main = m; probe.plan = p;
         probe.since = getTimer();
         app.addEventListener(Event.ACTIVATE, probe.activation);
         app.addEventListener(Event.DEACTIVATE, probe.activation);
         probe.write("agent-debug/heartbeat.json", JSON.stringify({runId:p.runId, phase:"boot"}));
         probe.timer.addEventListener("timer",probe.tick); probe.timer.start();
      }
      private function activation(e:Event):void
      { activity.push({type:e.type, at:getTimer(), phase:phase}); }
      private function field(o:*, key:String):*
      { var v:* = null; try { if(o != null && key in o) v = o[key]; } catch(e:*) {} return v; }
      private function scene():Object
      {
         var game:* = field(w,"game"), loc:* = field(w,"loc"), gg:* = field(w,"gg");
         return {scenario:plan.scenario, land:field(game,"curLandId"), loc:field(loc,"id"),
            locClass:loc == null ? null : getQualifiedClassName(loc),
            playerX:field(gg,"X"), playerY:field(gg,"Y"),
            stageWidth:main.stage.stageWidth, stageHeight:main.stage.stageHeight,
            frameRate:main.stage.frameRate, menu:field(field(w,"mm"),"active"),
            menuLoaded:field(field(w,"mm"),"loaded")};
      }
      private function advance(p:String):void
      {
         phase = p; since = getTimer();
         write("agent-debug/heartbeat.json",JSON.stringify({runId:plan.runId,phase:p}));
      }
      private function tick(e:Event):void
      {
         try
         {
            w = getDefinitionByName("fe.World")["w"];
            if(w != null && field(w,"verror") != null && w.verror.visible)
               throw new Error("game error: " + field(w.verror.txt,"text"));
            if(phase == "boot")
            {
               if(getTimer() - lastBootReport >= 5000)
               {
                  lastBootReport = getTimer();
                  var bootRecorder:Object = null, bootHost:* = main.getChildByName("ModSettingsCarrier");
                  if(bootHost != null && bootHost.frameRecorder != null) bootRecorder = bootHost.frameRecorder.status();
                  write("agent-debug/heartbeat.json", JSON.stringify({runId:plan.runId,phase:phase,
                     elapsedMs:getTimer()-since, scene:scene(), allLandsLoaded:field(w,"allLandsLoaded"),
                     textLoaded:field(w,"textLoaded"), musicLoaded:field(w,"musicLoaded"),
                     musicKol:field(w,"musicKol"), frameRecorder:bootRecorder}));
               }
               if(getTimer() - since > (plan.bootTimeoutMs > 0 ? plan.bootTimeoutMs : 60000)) throw new Error("boot/loader timeout");
               var data:Object = SharedObject.getLocal("ModLoader","/").data;
               if(data.boot == null || data.session == null || w == null) return;
               for each(var entry:String in plan.enabled) if(data["ok_" + entry] == null) return;
               // A World instance/loader OK can precede the menu's asynchronous resource boot.
               if(field(w.mm,"loaded") !== true || !w.allLandsLoaded || !w.textLoaded || w.musicLoaded < w.musicKol) return;
               if(plan.scenario == "menu") { advance("warmup"); return; }
               if(!w.allLandsLoaded) return;
               if(plan.scenario == "load")
               {
                  var saved:Object = w.getSave(plan.slot);
                  if(saved == null || saved.game == null)
                     throw new Error("requested save slot is absent in isolated seed");
                  // The menu's normal load path builds the GUI/sats skeleton without clearing this slot.
                  w.mm.active = false; w.newGame(plan.slot,"LP",null); advance("scene"); return;
               }
               w.mm.active = false; w.newGame(-1,"LP",null); advance("scene"); return;
            }
            if(phase == "scene")
            {
               if(getTimer() - since > 60000) throw new Error("scene timeout");
               if(w.gg == null || w.loc == null || field(w,"comLoad") >= 0 || field(w,"allStat") != 1) return;
               advance("warmup"); return;
            }
            if(phase == "warmup" && getTimer() - since >= plan.warmupMs)
            {
               firstScene = scene(); memoryStart = System.totalMemory; targetRate = main.stage.frameRate;
               if(plan.mode == "visual") { finish(null); return; }
               advance("sample"); timer.stop();
               began = previous = getTimer();
               main.stage.addEventListener(Event.ENTER_FRAME, frame);
            }
         }
         catch(err:*) { finish(String(err)); }
      }
      private function frame(e:Event):void
      {
         var now:int = getTimer(); frames.push(now - previous); previous = now;
         if(main.stage.frameRate != targetRate) rateChanged = true;
         if(now - began >= plan.measureMs)
         { main.stage.removeEventListener(Event.ENTER_FRAME,frame); finish(null); }
      }
      private function tree(o:DisplayObject, path:String, depth:int):void
      {
         // Breadth first: deep hidden menu timelines must not hide top-level mod overlays at the cap.
         var queue:Array = [{object:o,path:path,depth:depth}], cursor:int = 0;
         while(cursor < queue.length && nodes.length < 4000)
         {
         var current:Object = queue[cursor++];
         o = current.object; path = current.path; depth = current.depth;
         // Stage implements DisplayObject but several inherited getters are unsupported/null.
         var n:Object = {path:path,type:getQualifiedClassName(o),filters:[]};
         for each(var key:String in ["name","x","y","alpha","visible","width","height","scaleX","scaleY","rotation","blendMode"])
            n[key] = field(o,key);
         n.mask = field(field(o,"mask"),"name");
         var filters:* = field(o,"filters");
         if(filters != null) for each(var f:* in filters) n.filters.push(getQualifiedClassName(f));
         nodes.push(n);
         var c:DisplayObjectContainer = o as DisplayObjectContainer;
         if(c != null) for(var i:int=0;i<c.numChildren;i++)
         {
            if(queue.length >= 4001 || depth >= 40) { truncated = true; break; }
            queue.push({object:c.getChildAt(i),path:path+"/"+i,depth:depth+1});
         }
         }
         if(cursor < queue.length) truncated = true;
      }
      private function screenshot():void
      {
         var bitmap:BitmapData = new BitmapData(main.stage.stageWidth,main.stage.stageHeight,false,0);
         try
         {
            bitmap.draw(main.stage);
            var E:Class = getDefinitionByName("flash.display.PNGEncoderOptions") as Class;
            var bytes:* = Object(bitmap)["encode"](bitmap.rect,new E());
            var F:Class = getDefinitionByName("flash.filesystem.File") as Class;
            var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
            var s:* = new S(); s.open(F["applicationStorageDirectory"].resolvePath("agent-debug/frame.png"),"write");
            s.writeBytes(bytes); s.close();
         }
         finally { bitmap.dispose(); }
      }
      private function write(name:String, text:String):void
      {
         var F:Class = getDefinitionByName("flash.filesystem.File") as Class;
         var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var f:* = F["applicationStorageDirectory"].resolvePath(name); f.parent.createDirectory();
         var s:* = new S(); s.open(f,"write"); s.writeUTFBytes(text); s.close();
      }
      private function finish(error:String):void
      {
         timer.stop(); main.stage.removeEventListener(Event.ENTER_FRAME,frame);
         var end:Object = scene(), mem:Number = System.totalMemory;
         var seedExport:String = null;
         if(w != null && field(w,"verror") != null && w.verror.visible) error = "game error: "+field(w.verror.txt,"text");
         if(error == null && plan.mode == "visual")
         {
            try { screenshot(); tree(main.stage,"stage",0); write("agent-debug/tree.json",JSON.stringify({nodes:nodes,truncated:truncated})); }
            catch(e:*) { error = "visual capture failed after " + nodes.length + " tree nodes: " + String(e); }
         }
         if(error == null && plan.exportSave && plan.scenario == "new-game")
         {
            try
            {
               // Explicit diagnostic snapshot: saveGame may silently decline during tutorial dialogs.
               var oldSlot:int = w.autoSaveN;
               try { w.autoSaveN = 0; w.saveGame(-2); }
               finally { w.autoSaveN = oldSlot; }
               if(w.getSave(0).game == null) throw new Error("snapshot was not created");
               seedExport = "slot 0 after sampling; explicit isolated diagnostic snapshot";
            }
            catch(saveError:*) { seedExport = "failed: " + String(saveError); }
         }
         var recorder:Object = null, benchmark:Object = null, fault:Object = null;
         try
         {
            var host:* = main.getChildByName("ModSettingsCarrier");
            if(host != null && host.frameRecorder != null) recorder = host.frameRecorder.status();
            if(host != null) { benchmark = host.recorderBenchmark; fault = host.recorderFault; }
         }
         catch(recorderError:*) { recorder = {error:String(recorderError)}; }
         write("agent-debug/result.json",JSON.stringify({protocol:1,runId:plan.runId,appId:plan.appId,
            mode:plan.mode,error:error,framesMs:frames,sceneStart:firstScene,sceneEnd:end,
            memoryStart:memoryStart,memoryEnd:mem,rateChanged:rateChanged,activity:activity,seedExport:seedExport,
            frameRecorder:recorder,
            recorderBenchmark:benchmark, recorderFault:fault,
            loader:SharedObject.getLocal("ModLoader","/").data}));
         var application:* = getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"];
         if(plan.recorderExitCheck)
         {
            var observeExit:Function = function(event:Event):void
            {
               if(event.isDefaultPrevented()) return;
               write("agent-debug/recorder-exit.json", JSON.stringify({event:event.type, status:host.frameRecorder.status()}));
            };
            Object(main.stage)["nativeWindow"].addEventListener("closing", observeExit, false, -20000);
            Object(main.stage)["nativeWindow"].addEventListener(Event.CLOSE, observeExit, false, -20000);
            application.addEventListener("exiting", observeExit, false, -20000);
         }
         if(plan.closeWindow) Object(main.stage)["nativeWindow"].close();
         else
         {
            // AIR on this host did not dispatch the documented closing event for exit().
            // Sampling has ended; explicitly preserve memory telemetry before programmatic exit.
            try
            {
               if(host != null && host.frameRecorder != null && host.frameRecorder.saveForExit != null)
               {
                  var saved:Object = host.frameRecorder.saveForExit();
                  if(plan.recorderExitCheck)
                     write("agent-debug/recorder-exit.json", JSON.stringify({event:"explicit save before exit",status:saved}));
               }
            }
            catch(saveRecorderError:*) {}
            application.exit(error == null ? 0 : 1);
         }
      }
   }
}
