package
{
   import flash.display.Sprite;
   import flash.display.Loader;
   import flash.display.LoaderInfo;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.net.URLLoader;
   import flash.net.URLRequest;
   import flash.system.LoaderContext;
   import flash.utils.Dictionary;

   // T5: full = exactly the MainFE generic loader shape
   // (URLLoader manifest + parse + Dictionary + per-mod Loader.load, no init calls)
   public class ToyT5 extends Sprite
   {
      public var marks:Array;
      internal var manifestUrlLoader:URLLoader;
      internal var modEntryByLoader:Dictionary;

      public function ToyT5()
      {
         this.marks = new Array();
         mark("T5-ctor");
         try
         {
            this.manifestUrlLoader = new URLLoader();
            this.manifestUrlLoader.addEventListener(Event.COMPLETE,this.onManifestLoaded);
            this.manifestUrlLoader.addEventListener(IOErrorEvent.IO_ERROR,this.onManifestLoaderError);
            this.manifestUrlLoader.load(new URLRequest("app:/mods/loader-manifest.txt"));
         }
         catch(err:*)
         {
            mark("T5-err_loader");
         }
      }

      internal function onManifestLoaderError(param1:IOErrorEvent) : *
      {
         mark("T5-err_loader");
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
            mark("T5-boot-col" + colIdx);
         }
         catch(err:*)
         {
            mark("T5-err_parse");
         }
      }

      internal function onModSwfError(param1:IOErrorEvent) : *
      {
         var ldr:Loader;
         ldr = LoaderInfo(param1.currentTarget).loader;
         mark("T5-err_" + this.modEntryByLoader[ldr]);
      }

      internal function onModSwfLoaded(param1:Event) : *
      {
         var ldr:Loader;
         var entry:String;
         ldr = LoaderInfo(param1.currentTarget).loader;
         entry = String(this.modEntryByLoader[ldr]);
         mark("T5-ok_" + entry);
      }

      private function mark(key:String) : void
      {
         trace(key);
         try
         {
            this.marks.push(key);
         }
         catch(err:*)
         {
         }
      }
   }
}
