package
{
   import flash.display.Sprite;
   import flash.display.Loader;
   import flash.display.LoaderInfo;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.net.SharedObject;
   import flash.net.URLLoader;
   import flash.net.URLRequest;
   import flash.system.LoaderContext;
   import flash.utils.Dictionary;

   // 隔离实验：这段代码结构与 MainFE 通用 loader 完全一致（同样的
   // URLLoader/Dictionary/SharedObject/逐模组 Loader 构造）。先用 amxmlc 编译，
   // 再用 FFDec importScript 重编译一次（ToyLoaderFF.swf），
   // 对比两者在子装载下是否都能运行——判定 FFDec 编译器产物是否通过 AVM2 验证。
   // 不调用 cls.init（避免真实模组副作用），只记录 ok 标记。
   public class ToyLoader extends Sprite
   {
      internal var manifestUrlLoader:URLLoader;
      internal var modEntryByLoader:Dictionary;
      private var _log:FileStream;

      public function ToyLoader()
      {
         openLog();
         wlog("TOY-CTOR enter");
         try
         {
            this.loadModsFromManifest();
            wlog("TOY-CTOR ok");
         }
         catch (e:*)
         {
            wlog("TOY-CTOR THROW " + e.errorID + " " + e);
         }
      }

      internal function loadModsFromManifest() : *
      {
         try
         {
            this.manifestUrlLoader = new URLLoader();
            this.manifestUrlLoader.addEventListener(Event.COMPLETE,this.onManifestLoaded);
            this.manifestUrlLoader.addEventListener(IOErrorEvent.IO_ERROR,this.onManifestLoaderError);
            this.manifestUrlLoader.load(new URLRequest("app:/mods/loader-manifest.txt"));
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_loader","manifest load threw " + err);
         }
      }

      internal function onManifestLoaderError(param1:IOErrorEvent) : *
      {
         this.modLoaderStatus("err_loader","manifest IOError " + param1.text);
      }

      internal function onManifestLoaded(param1:Event) : *
      {
         var colIdx:int;
         var urlText:String;
         var lines:Array;
         var i:int;
         var parts:Array;
         var ldr:Loader;
         var ctxt:LoaderContext;
         try
         {
            urlText = this.loaderInfo.url;
            colIdx = 2;
            if(urlText.indexOf("pfeUI") >= 0)
            {
               colIdx = 4;
            }
            else if(urlText.indexOf("DLC") >= 0)
            {
               colIdx = 3;
            }
            this.modEntryByLoader = new Dictionary();
            lines = String(this.manifestUrlLoader.data).split("\n");
            for(i = 0; i < lines.length; i++)
            {
               parts = String(lines[i]).split("\r").join("").split("|");
               if(parts.length >= 5 && String(parts[0]).charAt(0) != "#" && parts[colIdx] == "1")
               {
                  ldr = new Loader();
                  ctxt = new LoaderContext(false);
                  this.modEntryByLoader[ldr] = String(parts[1]);
                  ldr.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onModSwfLoaded);
                  ldr.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onModSwfError);
                  ldr.load(new URLRequest("app:/mods/" + parts[0] + "/release/" + parts[1] + ".swf"),ctxt);
               }
            }
            this.modLoaderStatus("boot","col=" + colIdx);
         }
         catch(err:*)
         {
            this.modLoaderStatus("err_loader","manifest parse threw " + err);
         }
      }

      internal function onModSwfError(param1:IOErrorEvent) : *
      {
         var ldr:Loader;
         ldr = LoaderInfo(param1.currentTarget).loader;
         this.modLoaderStatus("err_" + this.modEntryByLoader[ldr],"IOError " + param1.text);
      }

      internal function onModSwfLoaded(param1:Event) : *
      {
         var ldr:Loader;
         var entry:String;
         ldr = LoaderInfo(param1.currentTarget).loader;
         entry = String(this.modEntryByLoader[ldr]);
         this.modLoaderStatus("ok_" + entry,"loaded (init NOT called in toy)");
      }

      internal function modLoaderStatus(key:String, message:String) : *
      {
         var so:SharedObject;
         trace("ModLoader[" + key + "] " + message);
         wlog("mark " + key + " " + message);
         try
         {
            so = SharedObject.getLocal("ToyLoaderFF","/");
            so.data[key] = message + " @" + new Date().time;
            so.flush();
         }
         catch(err:*)
         {
            wlog("sol-fail " + key + " " + err);
         }
      }

      private function openLog() : void
      {
         // 单一追加日志；变体标记延迟到 wlog 时判定（构造期 loaderInfo 可能未就绪）
         var f:File = new File("D:/Program Files/Steam/steamapps/common/Remains/mods/ModLoader/work/toyloader-both.log");
         try
         {
            _log = new FileStream();
            _log.open(f, FileMode.APPEND);
         }
         catch (e:*)
         {
            _log = null;
         }
      }

      private function tag() : String
      {
         try
         {
            if (this.loaderInfo != null && this.loaderInfo.url.indexOf("ToyLoaderFF") >= 0)
            {
               return "FF";
            }
         }
         catch (e:*)
         {
         }
         return "AMX";
      }

      private function wlog(s:String) : void
      {
         if (_log != null) { _log.writeUTFBytes("[" + tag() + "] " + s + "\n"); }
      }
   }
}
