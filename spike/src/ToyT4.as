package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.net.SharedObject;
   import flash.net.URLLoader;
   import flash.net.URLRequest;
   import flash.utils.Dictionary;

   // T4: T3 + Dictionary (fields + bracket assignment + lookup) - no Loader yet
   public class ToyT4 extends Sprite
   {
      internal var manifestUrlLoader:URLLoader;
      internal var modEntryByLoader:Dictionary;

      public function ToyT4()
      {
         mark("T4-ctor");
         try
         {
            this.manifestUrlLoader = new URLLoader();
            this.manifestUrlLoader.addEventListener(Event.COMPLETE,this.onManifestLoaded);
            this.manifestUrlLoader.addEventListener(IOErrorEvent.IO_ERROR,this.onManifestError);
            this.manifestUrlLoader.load(new URLRequest("app:/mods/loader-manifest.txt"));
         }
         catch(err:*)
         {
            mark("T4-load-throw");
         }
      }

      internal function onManifestError(param1:IOErrorEvent) : *
      {
         mark("T4-ioerror");
      }

      internal function onManifestLoaded(param1:Event) : *
      {
         var colIdx:int;
         var urlText:String;
         var lines:Array;
         var i:int;
         var parts:Array;
         var dummyObj:Object;
         try
         {
            urlText = this.loaderInfo.url;
            colIdx = 2;
            this.modEntryByLoader = new Dictionary();
            lines = String(this.manifestUrlLoader.data).split("\n");
            for(i = 0; i < lines.length; i++)
            {
               parts = String(lines[i]).split("\r").join("").split("|");
               if(parts.length >= 5 && String(parts[0]).charAt(0) != "#" && parts[colIdx] == "1")
               {
                  dummyObj = new Object();
                  this.modEntryByLoader[dummyObj] = String(parts[1]);
               }
            }
            mark("T4-dict-n" + this.modEntryByLoader.toString().length);
         }
         catch(err:*)
         {
            mark("T4-parse-throw");
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
