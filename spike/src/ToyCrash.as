package
{
   import flash.display.Sprite;

   // 精确复刻 MainFE 构造器首行（MainFE.as:20 stage.scaleMode = "noScale"）：
   // 不做 null 检查。若子装载 stage 为 null，构造器应抛 #1009，游戏初始化应失败
   // （表现为：无 INIT / 有 UNCAUGHT / content 异常），这就是方案 A 的死因判定。
   public class ToyCrash extends Sprite
   {
      public var marker:String = "TOY-CRASH-ALIVE";

      public function ToyCrash()
      {
         stage.scaleMode = "noScale";
         stage.align = "TL";
      }
   }
}
