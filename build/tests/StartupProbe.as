package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.net.SharedObject;
   import flash.utils.Timer;
   import flash.utils.getDefinitionByName;

   public class StartupProbe extends Sprite
   {
      private static var probe:StartupProbe;
      private var main:*, plan:Object, timer:Timer=new Timer(50);
      private var ticks:int=0, checks:int=0, lines:Array=[];
      public function StartupProbe() {}
      public static function init(m:*):void
      {
         probe=new StartupProbe();probe.main=m;
         var F:Class=getDefinitionByName("flash.filesystem.File") as Class;
         var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class,s:*=new S();
         s.open(F["applicationDirectory"].resolvePath("startup-scenario.json"),"read");
         probe.plan=JSON.parse(s.readUTFBytes(s.bytesAvailable));s.close();
         probe.timer.addEventListener("timer",probe.tick);probe.timer.start();
      }
      private function ok(value:Boolean,label:String):void
      {if(!value)throw new Error(label);checks++;lines.push("PASS "+label);}
      private function tick(e:Event):void
      {
         try
         {
            ticks++;
            var data:Object=SharedObject.getLocal("ModLoader","/").data;
            if(ticks>900)throw new Error("timeout: "+JSON.stringify(data));
            if(ticks<160)return;
            for each(var entry:String in plan.enabled)
            {
               if(entry=="ModLoaderMod" && plan.failure){if(data["err_"+entry]==null)return;}
               else if(data["ok_"+entry]==null)return;
            }
            ok(data.session!=null && data.boot!=null,"current loader session completed requests");
            for each(entry in plan.enabled)
            {
               ok(data["requested_"+entry]!=null,"requested "+entry);
               if(entry=="ModLoaderMod" && plan.failure)
                  ok(data["err_"+entry]!=null && data["ok_"+entry]==null,"expected runtime failure was reported");
               else ok(data["ok_"+entry]!=null,"initialized "+entry);
            }
            for each(entry in plan.disabled)
               ok(data["requested_"+entry]==null && data["ok_"+entry]==null,"disabled "+entry+" was not loaded");
            for(var key:String in data)
               if(key.indexOf("err_")==0)ok(plan.failure && key=="err_ModLoaderMod","no unexpected loader error: "+key);
            var host:*=main.getChildByName("ModSettingsCarrier");
            if(plan.content=="pfe.swf" && !plan.failure)
            {
               ok(host!=null && host.hostId=="ModLoader" && host.hostVersion=="2.2.0","embedded settings host published");
               ok(host.modAPI.apiVersion==1 && host.modAPI.menuVersion==1,"existing settings contract preserved");
            }
            else ok(host==null,"unsupported or failed settings runtime publishes no host");
            var w:*=getDefinitionByName("fe.World")["w"];
            ok(w==null || w.verror==null || !w.verror.visible,"no game error dialog");
            write("loader-state.json",JSON.stringify(data,null,2));finish(null);
         }
         catch(err:*){finish(String(err));}
      }
      private function write(name:String,text:String):void
      {
         var F:Class=getDefinitionByName("flash.filesystem.File") as Class,S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class,s:*=new S();
         s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeUTFBytes(text);s.close();
      }
      private function finish(error:String):void
      {
         timer.stop();lines.push(error==null?"PASS "+checks+" assertions":"FAIL "+error);
         write("startup-results.txt",lines.join("\n"));getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(error==null?0:1);
      }
   }
}
