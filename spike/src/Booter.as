package
{
   import flash.desktop.NativeApplication;
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.display.LoaderInfo;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.HTTPStatusEvent;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.events.UncaughtErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.utils.ByteArray;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;

   // R1 spike：外部 Loader 装载原版 pfe.swf，验证文档类构造期 stage 可用性。
   // 闸门：main.zastavka（public）存在且 visible==false ⇒ 游戏 onEnterFrameLoader 已跑完。
   public class Booter extends Sprite
   {
      private var _frame:int = 0;
      private var _game:Loader;
      private var _inited:Boolean = false;
      private var _opened:Boolean = false;
      private var _gateAt:int = -1;
      private var _stream:FileStream;
      private var _errs:Object = {};

      public function Booter()
      {
         trace("BOOTER-CTOR-ENTER");
         openLog();
         log("BOOTER-CTOR v=spike2 stageNotNull=" + (stage != null) +
             " appDir=" + safeAppDir());
         stage.frameRate = 30;
         stage.color = 0;
         var dom:ApplicationDomain = new ApplicationDomain(ApplicationDomain.currentDomain);
         _game = new Loader();
         var info:LoaderInfo = _game.contentLoaderInfo;
         info.addEventListener(Event.OPEN, onOpen);
         info.addEventListener(Event.INIT, onInit);
         info.addEventListener(Event.COMPLETE, onComplete);
         info.addEventListener(ProgressEvent.PROGRESS, onProgress);
         info.addEventListener(HTTPStatusEvent.HTTP_STATUS, onHttp);
         info.addEventListener(IOErrorEvent.IO_ERROR, onIOErr);
         info.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecErr);
         info.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaught);
         stage.addChild(_game);   // R1 关键：先入舞台，后 load
         // 实测：app:/ 流式对 15MB 卡 128KB、loadBytes 一律 #3226；改用 file:/// URL
         var gf:File = File.applicationDirectory.resolvePath("pfe.swf");
         log("LOAD-BEGIN " + gf.url);
         try
         {
            _game.load(new URLRequest(gf.url), new LoaderContext(false));
         }
         catch (le:Error)
         {
            log("LOAD-THROW " + le.message + " id=" + le.errorID);
         }
         log("LOAD-CALL-DONE");
         addEventListener(Event.ENTER_FRAME, onFrame);
      }

      private function onOpen(e:Event):void
      {
         _opened = true;
         log("GAME-OPEN url=" + (e.currentTarget as LoaderInfo).url);
      }

      private function onProgress(e:ProgressEvent):void
      {
         if (_frame % 30 == 0)
         {
            log("GAME-PROGRESS " + e.bytesLoaded + "/" + e.bytesTotal);
         }
      }

      private function onHttp(e:HTTPStatusEvent):void
      {
         log("GAME-HTTP status=" + e.status);
      }

      private function onInit(e:Event):void
      {
         var li:LoaderInfo = e.currentTarget as LoaderInfo;
         var main:* = li.content;
         _inited = true;
         log("GAME-INIT fired; contentClass=" + safeClass(main) +
             " contentStageNotNull=" + (main != null && DisplayObject(main).stage != null) +
             " url=" + li.url);
      }

      private function onComplete(e:Event):void
      {
         log("GAME-COMPLETE bytes=" + (e.currentTarget as LoaderInfo).bytesLoaded +
             "/" + (e.currentTarget as LoaderInfo).bytesTotal);
      }

      private function onIOErr(e:IOErrorEvent):void
      {
         log("RESULT=FAIL-IO " + e.text);
         exitApp(4);
      }

      private function onSecErr(e:SecurityErrorEvent):void
      {
         log("RESULT=FAIL-SECURITY " + e.text);
         exitApp(5);
      }

      private function onUncaught(e:UncaughtErrorEvent):void
      {
         var err:* = e.error;
         log("UNCAUGHT " + (err is Error ? (err as Error).errorID + " " + String(err) : String(err)));
      }

      private function onFrame(e:Event):void
      {
         _frame++;
         if (_frame % 60 == 0 && _frame < 1800 && !_inited)
         {
            var pl:LoaderInfo = _game.contentLoaderInfo;
            log("PROGRESS-TICK " + pl.bytesLoaded + "/" + pl.bytesTotal);
         }
         if (_gateAt < 0)
         {
            if (_frame > 1800)
            {
               var li:LoaderInfo = _game.contentLoaderInfo;
               log("RESULT=FAIL-TIMEOUT inited=" + _inited + " open=" + _opened +
                   " url=" + li.url +
                   " loaded=" + li.bytesLoaded + "/" + li.bytesTotal +
                   " content=" + safeClass(li.content));
               exitApp(3);
            }
            else if (_frame == 150 && !_inited)
            {
               log("NO-INIT-YET frame=" + _frame + " (waiting)");
            }
            if (_inited)
            {
               var main:* = _game.content;
               var z:* = null;
               try
               {
                  z = main.zastavka;
               }
               catch (err:*)
               {
                  if (!_errs["zastavka"])
                  {
                     _errs["zastavka"] = 1;
                     log("PROBE-zastavka-ERR " + err);
                  }
               }
               if (z != null && z.visible == false)
               {
                  _gateAt = _frame;
                  log("GATE-PASSED frame=" + _frame +
                      " stage=" + stage.stageWidth + "x" + stage.stageHeight +
                      " mainChildren=" + main.numChildren);
               }
            }
         }
         else if (_frame - _gateAt == 45)
         {
            dumpTree();
            log("RESULT=PASS");
            exitApp(0);
         }
      }

      private function dumpTree():void
      {
         var i:int;
         log("STAGE-CHILDREN n=" + stage.numChildren);
         for (i = 0; i < stage.numChildren; i++)
         {
            log("  stage[" + i + "] " + safeClass(stage.getChildAt(i)));
         }
         var main:* = _game.content;
         log("MAIN-CHILDREN n=" + main.numChildren);
         for (i = 0; i < main.numChildren; i++)
         {
            log("  main[" + i + "] " + safeClass(main.getChildAt(i)) +
                " vis=" + safeVisible(main.getChildAt(i)));
         }
      }

      private function safeVisible(o:*):String
      {
         var r:String = "?";
         try
         {
            r = String(o.visible);
         }
         catch (e:*)
         {
         }
         return r;
      }

      private function safeClass(o:*):String
      {
         var r:String = "null";
         if (o != null)
         {
            try
            {
               r = getQualifiedClassName(o);
            }
            catch (e:*)
            {
               r = "err";
            }
         }
         return r;
      }

      private function safeAppDir():String
      {
         var r:String = "?";
         try
         {
            r = File.applicationDirectory.nativePath;
         }
         catch (e:*)
         {
            r = "err";
         }
         return r;
      }

      private function openLog():void
      {
         var cands:Array = [];
         var f0:File = new File("D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader/spike/booter.log");
         cands.push(f0);
         try
         {
            cands.push(File.applicationDirectory.resolvePath("mods/ModLoader/spike/booter.log"));
            cands.push(File.applicationStorageDirectory.resolvePath("booter.log"));
         }
         catch (e:*)
         {
         }
         for each (var f:File in cands)
         {
            try
            {
               _stream = new FileStream();
               _stream.open(f, FileMode.WRITE);
               trace("BOOTER log at " + f.nativePath);
               return;
            }
            catch (e2:*)
            {
               _stream = null;
               trace("BOOTER log rejected " + f.nativePath + " : " + e2);
            }
         }
         trace("BOOTER NO LOG CHANNEL");
      }

      private function log(s:String):void
      {
         trace("BOOTER " + s);
         if (_stream != null)
         {
            _stream.writeUTFBytes(getTimer() + "ms f=" + _frame + " " + s + "\n");
         }
      }

      private function exitApp(code:int):void
      {
         if (_stream != null)
         {
            try
            {
               _stream.close();
            }
            catch (e:*)
            {
            }
            _stream = null;
         }
         NativeApplication.nativeApplication.exit(code);
      }
   }
}
