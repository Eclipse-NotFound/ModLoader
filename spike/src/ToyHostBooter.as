package
{
   import flash.desktop.NativeApplication;
   import flash.display.Loader;
   import flash.display.LoaderInfo;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.events.UncaughtErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.getTimer;

   // 载入两个 ToyLoader 变体（amxmlc 编译 vs FFDec 重编译），各驻留 8 秒，
   // 观察 INIT/UNCAUGHT——判定 FFDec 编译器产物能否通过 AVM2 验证并运行。
   public class ToyHostBooter extends Sprite
   {
      private var _log:FileStream;
      private var _files:Array = [];
      private var _idx:int = -1;
      private var _cur:Loader;
      private var _state:String = "idle";
      private var _dwellEnd:int = 0;
      private var _seen:int = 0;

      private function poll() : void
      {
         try
         {
            var c:* = _cur.content;
            if (c == null || c.marks == null) { return; }
            while (_seen < c.marks.length)
            {
               wlog("MARK " + _files[_idx] + " " + c.marks[_seen]);
               _seen++;
            }
         }
         catch (e:*)
         {
         }
      }

      public function ToyHostBooter()
      {
         var f:File = new File("D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader/work/toyhost.log");
         try { _log = new FileStream(); _log.open(f, FileMode.WRITE); } catch (e:*) { _log = null; }
         _files = readList();
         wlog("TOYHOST start n=" + _files.length);
         addEventListener(Event.ENTER_FRAME, tick);
         next();
      }

      private function readList() : Array
      {
         var result:Array = [];
         try
         {
            var lf:File = new File("D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader/work/toyhost-files.txt");
            var fs:FileStream = new FileStream();
            fs.open(lf, FileMode.READ);
            var raw:Array = String(fs.readUTFBytes(fs.bytesAvailable)).split("\n");
            fs.close();
            for (var i:int = 0; i < raw.length; i++)
            {
               var name:String = String(raw[i]).split("\r").join("");
               if (name.length > 0) { result.push(name); }
            }
         }
         catch (e:*)
         {
            wlog("LIST-READ-FAIL");
         }
         return result;
      }

      private function next() : void
      {
         _idx++;
         if (_idx >= _files.length)
         {
            wlog("TOYHOST done");
            if (_log) { try { _log.close(); } catch (e:*) {} _log = null; }
            NativeApplication.nativeApplication.exit(0);
            return;
         }
         _cur = new Loader();
         var info:LoaderInfo = _cur.contentLoaderInfo;
         info.addEventListener(Event.INIT, onInit);
         info.addEventListener(IOErrorEvent.IO_ERROR, onIO);
         info.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSec);
         info.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUnc);
         stage.addChild(_cur);
         var url:String = File.applicationDirectory.resolvePath("mods/ModLoader/spike/release/" + _files[_idx]).url;
         wlog("LOAD " + _files[_idx]);
         try
         {
            _cur.load(new URLRequest(url), new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain)));
         }
         catch (e:Error)
         {
            wlog("THROW " + e.errorID);
         }
         _state = "loading";
         _seen = 0;
         _dwellEnd = getTimer() + 10000;
      }

      private function onInit(e:Event) : void
      {
         wlog("INIT " + _files[_idx]);
         _state = "dwelling";
         _dwellEnd = getTimer() + 8000;
      }

      private function onIO(e:IOErrorEvent) : void { wlog("IO " + _files[_idx] + " " + e.text); advance(); }
      private function onSec(e:SecurityErrorEvent) : void { wlog("SEC " + _files[_idx]); advance(); }

      private function onUnc(e:UncaughtErrorEvent) : void
      {
         var err:* = e.error;
         wlog("UNCAUGHT " + _files[_idx] + " " + (err is Error ? (err as Error).errorID + ":" + String(err) : String(err)));
         advance();
      }

      private function advance() : void
      {
         if (_cur)
         {
            try { if (_cur.parent != null) { _cur.parent.removeChild(_cur); } } catch (e:*) {}
         }
         next();
      }

      private function tick(e:Event) : void
      {
         if (_cur != null && _cur.content != null) { poll(); }
         if (getTimer() > _dwellEnd)
         {
            if (_cur != null && _cur.content != null) { poll(); }
            wlog("TIMEOUT " + _files[_idx] + " state=" + _state + " marks=" + _seen);
            advance();
         }
      }

      private function wlog(s:String) : void
      {
         trace(s);
         if (_log != null) { _log.writeUTFBytes(getTimer() + "ms " + s + "\n"); }
      }
   }
}
