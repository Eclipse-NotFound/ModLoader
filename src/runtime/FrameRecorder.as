package
{
   import flash.display.Stage;
   import flash.events.Event;
   import flash.net.SharedObject;
   import flash.system.System;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;

   /** Passive bounded flight recorder. No display traversal, screenshots or gameplay writes. */
   public final class FrameRecorder
   {
      public static const VERSION:String = "1.0.0";
      private static var instance:FrameRecorder;
      private var stage:Stage, app:*, nativeWindow:*, F:Class, S:Class, directory:*;
      private var world:Class, loader:SharedObject;
      private var active:Boolean = false, focused:Boolean = false;
      private var previous:int, windowStart:int, frames:int, slow:int, longFrames:int, maximum:int;
      private var sequence:int = 0, samples:int = 0, writes:int = 0, dropped:int = 0;
      private var selfPeak:int = 0, budgetHits:int = 0;
      private var bad1:int = -60001, bad2:int = -60001, bad3:int = -60001;
      private var snapshotPeak:int = 0, exportMs:int = 0, exportedSequence:int = -1;
      private var exportError:String = "";
      private var stopped:String = "starting", session:String, startedEpoch:Number, origin:int;
      private var ring:Vector.<Object> = new Vector.<Object>(300, true);
      private var marks:Array = [], before:Object;
      private var slowThreshold:Number, longThreshold:Number;

      public function FrameRecorder() {}

      public static function start(main:*):void
      {
         if(instance != null) return;
         instance = new FrameRecorder();
         // Failure to record must never prevent settings or another mod from starting.
         try { instance.initialize(main); }
         catch(error:*) { instance.stop("init: " + String(error).substr(0, 180)); }
      }

      public static function readStatus():Object
      {
         return instance == null ? {active:false, reason:"not started"} : instance.status();
      }

      /** For a test driver immediately before programmatic exit, after measurement ends. */
      public static function saveForExit():Object
      {
         if(instance != null && instance.session != null)
            instance.exportOnExit(new Event("explicitRecorderExit"));
         return readStatus();
      }

      /** Pause/resume only a healthy recorder; failure/config-disabled states stay disabled. */
      public static function setSampling(enabled:Boolean):Boolean
      {
         if(instance == null) return false;
         return instance.toggle(enabled);
      }

      private function toggle(enabled:Boolean):Boolean
      {
         if(active) { if(!enabled) { if(frames > 0) dropped++; stop("paused by agent"); } return true; }
         if(!enabled) return stopped == "paused by agent";
         if(stopped != "paused by agent") return false;
         previous = windowStart = getTimer();
         frames = slow = longFrames = maximum = 0;
         focused = app.activeWindow != null; before = state(); thresholds();
         app.addEventListener(Event.ACTIVATE, focusChanged);
         app.addEventListener(Event.DEACTIVATE, focusChanged);
         active = true; stopped = "";
         stage.addEventListener(Event.ENTER_FRAME, tick, false, -1000);
         return true;
      }

      private function initialize(main:*):void
      {
         F = getDefinitionByName("flash.filesystem.File") as Class;
         S = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var config:* = F["applicationDirectory"].resolvePath("mods/ModLoader/release/telemetry.json");
         if(config.exists)
         {
            if(config.size > 4096) throw new Error("config exceeds 4096 bytes");
            var stream:* = new S();
            try
            {
               stream.open(config, "read");
               var settings:Object = JSON.parse(stream.readUTFBytes(stream.bytesAvailable));
               if(settings.enabled === false) { stopped = "disabled by config"; return; }
            }
            finally { stream.close(); }
         }
         stage = main.stage;
         if(stage == null) throw new Error("no stage");
         world = getDefinitionByName("fe.World") as Class;
         app = getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"];
         focused = app.activeWindow != null;
         loader = SharedObject.getLocal("ModLoader", "/"); // Read only; never flush.
         directory = F["applicationStorageDirectory"].resolvePath("frame-recorder");
         // No filesystem or JSON work during gameplay. Explicit NativeApplication.exit
         // dispatches window closing, but not application exiting: handle both paths.
         nativeWindow = Object(stage)["nativeWindow"];
         if(nativeWindow == null) throw new Error("no native window");
         nativeWindow.addEventListener("closing", exportOnExit, false, -10000);
         nativeWindow.addEventListener(Event.CLOSE, exportOnExit, false, -10000);
         app.addEventListener("exiting", exportOnExit, false, -10000);
         startedEpoch = new Date().time;
         session = startedEpoch.toFixed(0) + "-" + getTimer().toString(16);
         previous = windowStart = origin = getTimer();
         before = state();
         thresholds();
         app.addEventListener(Event.ACTIVATE, focusChanged);
         app.addEventListener(Event.DEACTIVATE, focusChanged);
         active = true; stopped = "";
         stage.addEventListener(Event.ENTER_FRAME, tick, false, -1000);
      }

      private function focusChanged(event:Event):void { focused = event.type == Event.ACTIVATE; }

      private function thresholds():void
      {
         var target:Number = 1000 / Math.max(1, stage.frameRate);
         slowThreshold = Math.max(50, target * 1.5);
         longThreshold = Math.max(100, target * 3);
      }

      private function identifier(value:*):*
      {
         return value == null ? null : String(value).substr(0, 100);
      }

      private function position():Object
      {
         var w:* = world["w"];
         if(w == null) return {focus:focused};
         return {land:w.game == null ? null : identifier(w.game.curLandId),
                 loc:w.loc == null ? null : identifier(w.loc.id),
                 x:w.gg == null ? null : w.gg.X, y:w.gg == null ? null : w.gg.Y,
                 allStat:w.allStat, paused:w.onPause, menu:w.mm == null ? null : w.mm.active,
                 error:w.verror != null && w.verror.visible, focus:focused};
      }

      private function state():Object
      {
         var result:Object = position(), w:* = world["w"], loc:* = w == null ? null : w.loc;
         result.targetFps = stage.frameRate;
         result.memoryBytes = System.totalMemory;
         // Array.length only. No object iteration or mutation of the world.
         if(loc != null)
         {
            result.units = loc.units == null ? 0 : loc.units.length;
            result.objects = loc.objs == null ? 0 : loc.objs.length;
            result.grenades = loc.grenades == null ? 0 : loc.grenades.length;
         }
         return result;
      }

      private function tick(event:Event):void
      {
         var now:int = getTimer(), dt:int = now - previous;
         previous = now;
         if(dt < 0) { stop("timer wrapped"); return; }
         frames++;
         if(dt > maximum) maximum = dt;
         if(dt >= slowThreshold) slow++;
         if(dt >= longThreshold)
         {
            longFrames++;
            if(marks.length < 4)
            {
               try
               {
                  marks.push({endMs:now - origin, dtMs:dt, after:position()});
                  checkBudget(getTimer() - now, "long frame snapshot");
                  if(!active) return;
               }
               catch(error:*) { stop("position: " + String(error).substr(0, 180)); return; }
            }
         }
         if(now - windowStart < 1000) return;
         try
         {
            capture(now);
            snapshotPeak = Math.max(snapshotPeak, getTimer() - now);
            var cost:int = getTimer() - now;
            checkBudget(cost, "recording work");
         }
         catch(failure:*) { stop("sample: " + String(failure).substr(0, 180)); }
      }

      private function capture(now:int):void
      {
         var after:Object = state(), elapsed:int = Math.max(1, now - windowStart);
         ring[sequence % 300] = {sequence:sequence, startMs:windowStart - origin, endMs:now - origin,
            elapsedMs:elapsed, frames:frames, fps:frames * 1000 / elapsed, maxMs:maximum,
            slowFrames:slow, longFrames:longFrames, omittedMarks:longFrames - marks.length,
            before:before, after:after, stalls:marks};
         sequence++; samples++; before = after;
         thresholds(); frames = slow = longFrames = maximum = 0; marks = [];
         windowStart = now;
      }

      private function loaderState():Object
      {
         var data:Object = loader.data, loaded:Array = [], errors:Array = [], count:int = 0;
         for(var key:String in data)
         {
            if(++count > 256) break;
            if(key.indexOf("ok_") == 0) loaded.push(key.substr(3, 100));
            if(key.indexOf("err_") == 0) errors.push({mod:key.substr(4, 100), error:String(data[key]).substr(0, 300)});
         }
         return {session:data.session, loaded:loaded, errors:errors, truncated:count > 256};
      }

      private function exportOnExit(event:Event):void
      {
         if(event.isDefaultPrevented() || exportedSequence == sequence) return;
         var began:int = getTimer();
         var stream:* = null;
         try
         {
            // Some exit paths already disposed the stage. Keep complete evidence
            // even when the last partial window can no longer be sampled.
            if(active && frames > 0)
            {
               try { capture(began); }
               catch(partialError:*) { dropped++; }
            }
            if(sequence == 0) return;
            directory.createDirectory();
            var temporary:* = directory.resolvePath("frames-v1.pending");
            stream = new S(); stream.open(temporary, "write");
            var load:Object = loaderState(), first:int = Math.max(0, sequence - 300);
            for(var i:int = first; i < sequence; i += 5)
            {
               var batch:Array = [];
               for(var j:int = i; j < Math.min(i + 5, sequence); j++) batch.push(ring[j % 300]);
               var text:String = JSON.stringify({schema:1, version:VERSION, session:session,
                  startedEpochMs:startedEpoch, clockOriginMs:origin, writtenMs:began - origin,
                  selfPeakMs:selfPeak, droppedSamples:dropped, loader:load,
                  recorder:status(), samples:batch}) + "\n";
               if(text.length > 16000) throw new Error("chunk exceeds character cap");
               stream.writeUTFBytes(text); // UTF-8 <= 64000 bytes per bounded batch.
            }
            stream.close(); stream = null;
            temporary.moveTo(directory.resolvePath("frames-v1.jsonl"), true);
            writes++; exportedSequence = sequence; exportError = "";
         }
         catch(error:*) { exportError = String(error).substr(0, 180); }
         finally
         {
            try { if(stream != null) stream.close(); } catch(ignored:*) {}
            exportMs = getTimer() - began;
         }
         // Never prevent closing, call exit(), force GC, or change the requested exit code.
      }

      private function checkBudget(cost:int, context:String):void
      {
         selfPeak = Math.max(selfPeak, cost);
         if(cost < 4 || (!active && stopped != "paused by agent")) return;
         budgetHits++;
         bad1 = bad2; bad2 = bad3; bad3 = getTimer();
         // Rare isolated scheduler delays must not accumulate forever. Preserve
         // the first failure reason; a later 0 ms completion is not the failure.
         if(cost >= 20 || (bad1 >= 0 && bad3 - bad1 <= 60000))
            stop(context + " exceeded budget: " + cost + " ms");
      }

      private function stop(reason:String):void
      {
         active = false; stopped = reason; marks = [];
         if(stage != null) stage.removeEventListener(Event.ENTER_FRAME, tick);
         if(app != null)
         {
            app.removeEventListener(Event.ACTIVATE, focusChanged);
            app.removeEventListener(Event.DEACTIVATE, focusChanged);
         }
         // Keep bounded evidence and exit listeners even after sampling stops.
      }

      public function status():Object
      {
         return {version:VERSION, active:active, reason:stopped, session:session, clockOriginMs:origin,
            samples:samples, writes:writes, droppedSamples:dropped, selfPeakMs:selfPeak,
            snapshotPeakMs:snapshotPeak, exportMs:exportMs, exportError:exportError,
            overBudgetEvents:budgetHits,
            bufferedSamples:Math.min(sequence, 300), mode:"memory-until-exit",
            directory:directory == null ? null : directory.nativePath};
      }
   }
}
