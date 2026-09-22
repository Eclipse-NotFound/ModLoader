package
{
   import flash.display.Sprite;
   import flash.events.Event;

   // 最小 R1 判定对象：构造器触碰 stage（与 MainFE.as:20 相同动作），但不抛——
   // 把结果存进 public 变量，由 booter 读回。另含一个 public var 计数器（ENTER_FRAME 驱动，
   // 模拟 MainFE.onEnterFrameLoader 的自听帧循环）。
   public class ToyGame extends Sprite
   {
      public var ctorStageNotNull:Boolean = false;
      public var frames:int = 0;
      public var marker:String = "TOY-ALIVE";

      public function ToyGame()
      {
         ctorStageNotNull = (stage != null);
         if (ctorStageNotNull)
         {
            stage.scaleMode = "noScale";
         }
         addEventListener(Event.ENTER_FRAME, onFrame);
      }

      private function onFrame(e:Event):void
      {
         frames++;
      }
   }
}
