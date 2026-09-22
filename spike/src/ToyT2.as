package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.net.SharedObject;
   import flash.net.URLLoader;
   import flash.net.URLRequest;

   // T2: T1 + URLLoader read of the real manifest (no parsing yet)
   public class ToyT2 extends Sprite
   {
      internal var manifestUrlLoader:URLLoader;

      public function ToyT2()
      {
         mark("T2-ctor");
         try
         {
            this.manifestUrlLoader = new URLLoader();
            this.manifestUrlLoader.addEventListener(Event.COMPLETE,this.onManifestLoaded);
            this.manifestUrlLoader.addEventListener(IOErrorEvent.IO_ERROR,this.onManifestError);
            this.manifestUrlLoader.load(new URLRequest("app:/mods/loader-manifest.txt"));
         }
         catch(err:*)
         {
            mark("T2-load-throw");
         }
      }

      internal function onManifestError(param1:IOErrorEvent) : *
      {
         mark("T2-ioerror");
      }

      internal function onManifestLoaded(param1:Event) : *
      {
         mark("T2-len-" + String(this.manifestUrlLoader.data).length);
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
