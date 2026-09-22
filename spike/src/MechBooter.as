package
{
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.display.LoaderInfo;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.ByteArray;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;
   import flash.desktop.NativeApplication;

   // 机制探测：对 ToyGame.swf 依次尝试不同加载路径，找出在 extendedDesktop
   // 沙箱下能让"文档类构造器触碰 stage"的子 SWF 成功初始化、且 booter 可读其
   // public 成员的那一种。每种尝试结果写一行 ATTEMPT-n 日志。
   public class MechBooter extends Sprite
   {
      private var _log:FileStream;
      private var _step:int = 0;
      private var _data:ByteArray;
      private var _tries:Array = [];
      private var _cur:Loader;
      private var _curName:String = "";
      private var _curResult:String = "";
      private var _deadline:int = 0;

      public function MechBooter()
      {
         openLog();
         log("MECH-BOOT v=1");
         var gf:File = File.applicationDirectory.resolvePath("mods/ModLoader/spike/release/ToyGame.swf");
         try
         {
            var fs:FileStream = new FileStream();
            fs.open(gf, FileMode.READ);
            _data = new ByteArray();
            fs.readBytes(_data, 0, fs.bytesAvailable);
            fs.close();
            log("TOY-SIZE " + _data.length);
         }
         catch (e:Error)
         {
            log("TOY-READ-FAIL " + e.message);
            done();
            return;
         }
         addEventListener(Event.ENTER_FRAME, tick);
         next();
      }

      private function next():void
      {
         _curResult = "";
         if (_step >= 5)
         {
            summary();
            done();
            return;
         }
         _cur = new Loader();
         var info:LoaderInfo = _cur.contentLoaderInfo;
         var name:String = "";
         var idx:int = _step;
         switch (idx)
         {
            case 0:
               name = "load(app:/..., LC(false)) 默认子域";
               wire(info);
               stage.addChild(_cur);
               _cur.load(new URLRequest("app:/mods/ModLoader/spike/release/ToyGame.swf"), new LoaderContext(false));
               break;
            case 1:
               name = "load(app:/..., LC(false, currentDomain)) 合并当前域";
               wire(info);
               stage.addChild(_cur);
               _cur.load(new URLRequest("app:/mods/ModLoader/spike/release/ToyGame.swf"),
                         new LoaderContext(false, ApplicationDomain.currentDomain));
               break;
            case 2:
               name = "loadBytes(LC(false)) 默认子域";
               wire(info);
               stage.addChild(_cur);
               try { _cur.loadBytes(_data, new LoaderContext(false)); }
               catch (e:Error) { finish(name, "THROW " + e.errorID + " " + e.message); return; }
               break;
            case 3:
               name = "loadBytes(LC(false, new ApplicationDomain(current))) 显式子域";
               wire(info);
               stage.addChild(_cur);
               try { _cur.loadBytes(_data, new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain))); }
               catch (e:Error) { finish(name, "THROW " + e.errorID + " " + e.message); return; }
               break;
            case 4:
               name = "load(file:///..., LC(false)) 文件URL+默认子域";
               wire(info);
               stage.addChild(_cur);
               _cur.load(new URLRequest(File.applicationDirectory.resolvePath("mods/ModLoader/spike/release/ToyGame.swf").url),
                         new LoaderContext(false));
               break;
         }
         _curName = name;
         _deadline = getTimer() + 4000;
      }

      private function wire(info:LoaderInfo):void
      {
         info.addEventListener(Event.INIT, onInit);
         info.addEventListener(IOErrorEvent.IO_ERROR, onIO);
         info.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSec);
         info.addEventListener(ProgressEvent.PROGRESS, onProg);
      }

      private function onProg(e:ProgressEvent):void
      {
         // 只在卡住时不刷；正常本地很快
      }

      private function onInit(e:Event):void
      {
         var li:LoaderInfo = e.currentTarget as LoaderInfo;
         var c:* = li.content;
         var s:String = "INIT class=" + getQualifiedClassName(c);
         if (c != null)
         {
            try { s += " ctorStageNotNull=" + c.ctorStageNotNull + " marker=" + c.marker; }
            catch (err:Error) { s += " READ-PUBLIC-FAIL " + err.errorID + " " + err.message; }
         }
         finish(_curName, s);
      }

      private function onIO(e:IOErrorEvent):void
      {
         finish(_curName, "IO_ERROR " + e.text);
      }

      private function onSec(e:SecurityErrorEvent):void
      {
         finish(_curName, "SECURITY " + e.text);
      }

      private function finish(name:String, result:String):void
      {
         if (_curResult != "") return; // 本次已结束
         _curResult = result;
         _tries.push("ATTEMPT " + name + " => " + result);
      }

      private function tick(e:Event):void
      {
         if (_curResult != "")
         {
            // 给已结束的下一次；等 60ms 让子内容跑几帧
            _step++;
            _curResult = "";
            try { if (_cur && DisplayObject(_cur).parent) DisplayObject(_cur).parent.removeChild(_cur); } catch (er:*) {}
            next();
            return;
         }
         if (_cur != null && _cur.contentLoaderInfo != null && _cur.content != null)
         {
            // 已 INIT 但 finish 已处理；等超时或内容
         }
         if (getTimer() > _deadline)
         {
            finish(_curName, "TIMEOUT (no INIT/IO/SEC in 4s)");
         }
      }

      private function summary():void
      {
         for each (var line:String in _tries) log(line);
         if (_tries.length < 5) log("MECH tried=" + _tries.length + " of 5");
         log("MECH-END");
      }

      private function openLog():void
      {
         var f:File = new File("D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader/spike/mech.log");
         try
         {
            _log = new FileStream();
            _log.open(f, FileMode.WRITE);
         }
         catch (e:Error)
         {
            _log = null;
         }
      }

      private function log(s:String):void
      {
         trace(s);
         if (_log != null) _log.writeUTFBytes(getTimer() + "ms " + s + "\n");
      }

      private function done():void
      {
         if (_log != null) { try { _log.close(); } catch (e:*) {} _log = null; }
         NativeApplication.nativeApplication.exit(0);
      }
   }
}
