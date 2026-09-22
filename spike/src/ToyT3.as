package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.net.SharedObject;
   import flash.net.URLLoader;
   import flash.net.URLRequest;

   // T3: T2 + full manifest parsing (split/join/charAt/indexOf loop)
   public class ToyT3 extends Sprite
   {
      internal var manifestUrlLoader:URLLoader;

      public function ToyT3()
      {
         mark("T3-ctor");
         try
         {
            this.manifestUrlLoader = new URLLoader();
            this.manifestUrlLoader.addEventListener(Event.COMPLETE,this.onManifestLoaded);
            this.manifestUrlLoader.addEventListener(IOErrorEvent.IO_ERROR,this.onManifestError);
            this.manifestUrlLoader.load(new URLRequest("app:/mods/loader-manifest.txt"));
         }
         catch(err:*)
         {
            mark("T3-load-throw");
         }
      }

      internal function onManifestError(param1:IOErrorEvent) : *
      {
         mark("T3-ioerror");
      }

      internal function onManifestLoaded(param1:Event) : *
      {
         var colIdx:int;
         var urlText:String;
         var lines:Array;
         var i:int;
         var parts:Array;
         var count:int;
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
            lines = String(this.manifestUrlLoader.data).split("\n");
            for(i = 0; i < lines.length; i++)
            {
               parts = String(lines[i]).split("\r").join("").split("|");
               if(parts.length >= 5 && String(parts[0]).charAt(0) != "#" && parts[colIdx] == "1")
               {
                  count++;
               }
            }
            mark("T3-parsed-col" + colIdx + "-n" + count);
         }
         catch(err:*)
         {
            mark("T3-parse-throw");
         }
      }

      private function mark(key:String) : void
      {
         var so:SharedObject;
         trace(key);
         try
         {
            so = SharedObject.getLocal("ToyProbe","/");
            so.data[key] = "@" + new Date().time;
            so.flush();
         }
         catch(err:*)
         {
         }
      }
   }
}
