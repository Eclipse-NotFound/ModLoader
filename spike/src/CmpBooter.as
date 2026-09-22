package
{
   import flash.desktop.NativeApplication;
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.display.LoaderInfo;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.events.UncaughtErrorEvent;
   import flash.filesystem.File;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.getTimer;
   import flash.filesystem.FileStream;
   import flash.filesystem.FileMode;

   // 对照：ToyGame(null-safe 构造器) vs ToyCrash(stage. 直写构造器)。
   // 两者用同一加载机制（load app:/ LC(false) 子域）。若 ToyCrash 报 #1009/无 content
   // 而 ToyGame 正常，则证明"子装载构造期 stage=null"是真实约束 → 方案 A 需靠
   // 让游戏在主文档构造后再注入的方式，而非直接 Loader 装载整个 pfe.swf。
   public class CmpBooter extends Sprite
   {
      private var _log:FileStream;
      private var _idx:int = 0;
      private var _files:Array = ["ToyGame.swf", "BigToy.swf", "ToyCrash.swf"];
      private var _cur:Loader;
      private var _done:Boolean = false;
      private var _deadline:int = 0;
      private var _lastProg:String = "-";

      public function CmpBooter()
      {
         var f:File = new File("D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader/spike/cmp.log");
         try { _log = new FileStream(); _log.open(f, FileMode.WRITE); } catch (e:*) { _log = null; }
         wlog("CMP-BOOT");
         next();
      }

      private function next():void
      {
         if (_idx >= _files.length) { wlog("CMP-END"); finish(); return; }
         var name:String = _files[_idx];
         _done = false;
         _lastProg = "-";
         _cur = new Loader();
         var info:LoaderInfo = _cur.contentLoaderInfo;
         info.addEventListener(Event.INIT, OnInit);
         info.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent):void {
            _lastProg = e.bytesLoaded + "/" + e.bytesTotal;
         });
         info.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void { r(name, "IO " + e.text); });
         info.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent):void { r(name, "SEC " + e.text); });
         info.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, function(e:UncaughtErrorEvent):void {
            var err:* = e.error;
            r(name, "UNCAUGHT " + (err is Error ? (err as Error).errorID + ":" + String(err) : String(err)));
         });
         stage.addChild(_cur);
         var url:String = File.applicationDirectory.resolvePath("mods/ModLoader/spike/release/" + name).url;
         wlog("LOAD " + name + " url=" + url);
         try
         {
            _cur.load(new URLRequest(url), new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain)));
         }
         catch (e:Error) { r(name, "THROW " + e.errorID); }
         _deadline = getTimer() + 20000;
         addEventListener(Event.ENTER_FRAME, tick);
      }

      private function tick(e:Event):void
      {
         if (!_done && getTimer() > _deadline) { r(_files[_idx], "TIMEOUT-NO-INIT lastProg=" + _lastProg); }
      }

      private function OnInit(e:Event):void
      {
         var li:LoaderInfo = e.currentTarget as LoaderInfo;
         var c:* = li.content;
         var s:String = "INIT content=" + (c == null ? "null" : "ok");
         try { s += " marker=" + c.marker + " ctorStage=" + c.ctorStageNotNull + " prog=" + _lastProg; } catch (er:*) { s += " marker-ERR " + er.errorID; }
         r(_files[_idx], s);
      }

      private function r(name:String, result:String):void
      {
         if (_done) return;
         _done = true;
         removeEventListener(Event.ENTER_FRAME, tick);
         wlog("RESULT " + name + " => " + result);
         if (_cur)
         {
            try
            {
               if (DisplayObject(_cur).parent != null) DisplayObject(_cur).parent.removeChild(_cur);
            }
            catch (e:*)
            {
            }
         }
         _idx++;
         next();
      }

      private function wlog(s:String):void
      {
         trace(s);
         if (_log != null) _log.writeUTFBytes(getTimer() + "ms " + s + "\n");
      }

      private function finish():void
      {
         if (_log != null) { try { _log.close(); } catch (e:*) {} _log = null; }
         NativeApplication.nativeApplication.exit(0);
      }
   }
}
