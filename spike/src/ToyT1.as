package
{
   import flash.display.Sprite;
   import flash.net.SharedObject;

   // T1: SharedObject only (production-proven under FFDec - baseline, must pass)
   public class ToyT1 extends Sprite
   {
      public function ToyT1()
      {
         mark("T1-ctor");
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
