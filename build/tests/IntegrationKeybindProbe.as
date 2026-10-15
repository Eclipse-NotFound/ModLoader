package
{
   import flash.display.Sprite;
   import flash.display.BitmapData;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.utils.Timer;
   import flash.utils.getDefinitionByName;

   /** Installed game, candidate clients, real settings buttons and fresh reload. */
   public class IntegrationKeybindProbe extends Sprite
   {
      private static var self:IntegrationKeybindProbe;
      private var main:*,w:*,api:*,timer:Timer=new Timer(50);
      private var ticks:int,phase:int,since:int,checks:int,pageAt:int;
      private var run:String,log:String="",expected:Array,actions:Array=[];
      private var counts:Object={"msw-hotkeys":2,"sandevistan-hotkeys":1,"realisticvision-hotkeys":3,
         "rconnect-hotkeys":2,"randomrooms-hotkeys":8,"firearmattachments-hotkeys":5,"light-and-darkness-hotkeys":2};
      public function IntegrationKeybindProbe(){}
      public static function init(m:*):void
      {
         self=new IntegrationKeybindProbe();self.main=m;
         self.run=self.readApp("scenario.txt").split(":")[1];
         self.expected=self.readApp("keybind-pages.txt").split(",");
         self.write("probe-init.txt",self.run+" "+self.expected.join(","));
         self.timer.addEventListener("timer",self.tick);self.timer.start();
      }
      private function ok(v:Boolean,label:String):void{if(!v)throw new Error(label);checks++;log+="PASS "+label+"\n";}
      private function advance(n:int):void{phase=n;since=ticks;}
      private function page(id:String):Object{for each(var p:Object in api.getPages())if(p.modId==id)return p;return null;}
      private function event(code:int,down:Boolean=true,ctrl:Boolean=false,alt:Boolean=false,shift:Boolean=false):KeyboardEvent
      {return new KeyboardEvent(down?KeyboardEvent.KEY_DOWN:KeyboardEvent.KEY_UP,true,true,0,code,0,ctrl,alt,shift);}
      private function press(code:int,ctrl:Boolean=false,alt:Boolean=false,shift:Boolean=false):void
      {main.stage.dispatchEvent(event(code,true,ctrl,alt,shift));main.stage.dispatchEvent(event(code,false,ctrl,alt,shift));}
      private function binding(a:Object,extra:Boolean=false):KeyboardEvent{return event(a.code,true,true,true,extra);}
      private function action(id:String,key:String):Object{for each(var a:Object in actions)if(a.page==id&&a.key==key)return a;return null;}
      private function same(v:*,a:Object):Boolean{return v.code==a.code&&v.ctrl&&v.alt&&!v.shift;}
      private function tick(e:Event):void
      {
         try
         {
            ticks++;if(ticks%10==0)write("heartbeat.txt","phase="+phase+" ticks="+ticks+"\n"+log);
            if(ticks>1900)throw new Error("timeout phase="+phase);
            w=getDefinitionByName("fe.World")["w"];if(w==null)return;
            if(w.verror&&w.verror.visible)throw new Error(w.verror.txt.text);
            var carrier:*=main.getChildByName("ModSettingsCarrier");if(carrier==null)return;api=carrier.modAPI;
            if(phase==0)
            {
               if(!w.allLandsLoaded)return;
               for each(var id:String in expected)if(page(id)==null)return;
               var sequence:int=0;
               for each(id in expected)
               {
                  var p:Object=page(id),n:int=0;
                  for each(var it:Object in p.items)if(it.kind=="keybind")
                  {actions.push({page:id,key:it.key,item:it,code:65+sequence++});n++;}
                  ok(n==counts[id],id+" publishes the expected action count");
                  ok(p.featureOrder==99&&p.featureName=="快捷键",id+" is inside its module shortcut menu");
               }
               ok(actions.length<=23&&actions.length>0,"each shortcut has one authoritative item");
               if(run!="reload"&&page("rconnect-hotkeys")&&page("realisticvision-hotkeys"))
                  ok(api.keyConflict("rconnect-hotkeys","panel",{code:121,ctrl:false,alt:false,shift:false})!="","the existing shared F10 conflict is visible");
               w.mm.active=false;w.newGame(-1,"LP",null);advance(1);return;
            }
            if(phase==1)
            {
               if(w.gg==null||w.loc==null||ticks-since<110)return;
               w.lang="zh";w.gui.dialScript.running=false;w.gui.guiPause=false;
               w.pip.onoff(5);advance(2);return;
            }
            if(phase==2&&ticks-since>5)
            {
               if(pageAt>=expected.length){advance(4);return;}
               ok(api.selectPage(expected[pageAt]),expected[pageAt]+" opens through the native menu");advance(3);return;
            }
            if(phase==3&&ticks-since>4)
            {
               id=expected[pageAt];
               for each(var a:Object in actions)if(a.page==id)
               {
                  var button:*=find(main,"SettingsKeyChange:"+a.key);
                  ok(button!=null&&button.visible,id+"/"+a.key+" has a visible change button");
                  if(run=="reload")ok(same(a.item["get"](),a),id+"/"+a.key+" survives a fresh process");
                  else
                  {
                     button.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
                     ok(api.isCapturingKey(),id+"/"+a.key+" captures from its own menu button");
                     press(a.code,true,true);
                     ok(!api.isCapturingKey()&&same(a.item["get"](),a),id+"/"+a.key+" accepts and saves the new combination");
                  }
                  ok(api.matchesKey(id,a.key,binding(a))&&!api.matchesKey(id,a.key,binding(a,true)),id+"/"+a.key+" matches exact modifiers");
               }
               advance(7);return;
            }
            if(phase==7&&ticks-since>4)
            {
               id=expected[pageAt];
               for each(a in actions)if(a.page==id)
               {
                  var currentButton:*=find(main,"SettingsKeyChange:"+a.key);
                  ok(textOf(currentButton).indexOf("Ctrl+Alt+"+String.fromCharCode(a.code))>=0,id+"/"+a.key+" displays its current binding");
                  var caption:*=currentButton.getChildAt(0);
                  ok(caption.textHeight<=caption.height-4&&caption.textWidth<=caption.width-4,id+"/"+a.key+" text fits its button ("+caption.textHeight+"/"+caption.height+", "+caption.textWidth+"/"+caption.width+")");
               }
               screenshot("menu-"+id+"-"+run+".png");pageAt++;advance(2);return;
            }
            if(phase==4)
            {
               if(run!="reload")
               {
                  var first:Object=actions[0],second:Object=actions[1];
                  api.beginKeyCapture(first.page,first.key);press(second.code,true,true);
                  ok(api.isCapturingKey()&&same(first.item["get"](),first),"cross-module duplicates leave the previous binding intact");press(27);
                  api.clearKey(first.page,first.key);ok(first.item["get"]().code==0,"a real client action can be cleared");
                  api.beginKeyCapture(first.page,first.key);press(first.code,true,true);
                  ok(same(first.item["get"](),first),"the cleared real client action can be rebound");
               }
               w.pip.onoff(-1);w.gui.dialScript.running=false;w.gui.guiPause=false;main.stage.focus=null;advance(5);return;
            }
            if(phase==5&&ticks-since>5)
            {
               var toggle:Object=action("realisticvision-hotkeys","toggle"),mode:Object=action("realisticvision-hotkeys","mode");
               if(toggle!=null)
               {
                  var config:String=readStore("RealisticVision_config.txt");
                  press(122);ok(readStore("RealisticVision_config.txt")==config,"old F11 no longer toggles vision");
                  press(toggle.code,true,true,true);ok(readStore("RealisticVision_config.txt")==config,"extra modifier does not toggle vision");
                  press(toggle.code,true,true);var changed:String=readStore("RealisticVision_config.txt");
                  ok(changed!=config,"the rebound vision toggle executes the real action");
                  press(mode.code,true,true);ok(readStore("RealisticVision_config.txt")!=changed,"the rebound vision mode executes the real action");
               }
               var panel:Object=action("rconnect-hotkeys","panel"),chat:Object=action("rconnect-hotkeys","chat"),hud:*=find(main.stage,"rconnect-hud");
               if(panel!=null)
               {
                  ok(hud!=null,"the real co-op panel is present");var was:Boolean=hud.visible;
                  press(121);ok(hud.visible==was,"old F10 no longer toggles the co-op panel");
                  press(panel.code,true,true,true);ok(hud.visible==was,"extra modifier does not toggle the co-op panel");
                  main.stage.dispatchEvent(binding(panel));ok(hud.visible!=was,"the rebound panel action runs");
                  main.stage.dispatchEvent(binding(panel));ok(hud.visible!=was,"system repeat does not toggle the panel again");
                  main.stage.dispatchEvent(event(panel.code,false,true,true));press(panel.code,true,true);
                  ok(hud.visible==was,"release and repress toggles the panel again");
                  press(chat.code,true,true);advance(6);return;
               }
               finish();return;
            }
            if(phase==6&&ticks-since>4)
            {
               hud=find(main.stage,"rconnect-hud");var chatLog:*=find(main.stage,"rconnect-chat-log");
               ok(hud.visible&&!hud.collapsed&&chatLog.visible,"the rebound chat action opens the actual chat page");
               screenshot("co-op-rebound-chat-"+run+".png");finish();return;
            }
         }
         catch(error:*){write(run+"-results.txt",log+"FAIL "+error+"\n"+error.getStackTrace());shutdown(1);}
      }
      private function find(o:*,name:String):*
      {if(o==null)return null;if(o.name==name)return o;if("numChildren" in o)for(var i:int=0;i<o.numChildren;i++){var r:*=find(o.getChildAt(i),name);if(r!=null)return r;}return null;}
      private function textOf(o:*):String
      {if(o==null)return "";var s:String="text" in o?o.text:"";if("numChildren" in o)for(var i:int=0;i<o.numChildren;i++)s+=textOf(o.getChildAt(i));return s;}
      private function fileText(f:*):String
      {if(!f.exists)return "";var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;var s:*=new S();s.open(f,"read");var t:String=s.readUTFBytes(s.bytesAvailable);s.close();return t;}
      private function readApp(path:String):String{return fileText(getDefinitionByName("flash.filesystem.File")["applicationDirectory"].resolvePath(path));}
      private function readStore(path:String):String{return fileText(getDefinitionByName("flash.filesystem.File")["applicationStorageDirectory"].resolvePath(path));}
      private function write(name:String,text:String):void
      {var F:Class=getDefinitionByName("flash.filesystem.File") as Class;var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;var s:*=new S();s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeUTFBytes(text);s.close();}
      private function screenshot(name:String):void
      {var st:*=main.stage;var b:BitmapData=new BitmapData(st.stageWidth,st.stageHeight,false,0);b.draw(st);var E:Class=getDefinitionByName("flash.display.PNGEncoderOptions") as Class;var bytes:*=Object(b)["encode"](b.rect,new E());var F:Class=getDefinitionByName("flash.filesystem.File") as Class;var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;var s:*=new S();s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeBytes(bytes);s.close();b.dispose();}
      private function finish():void
      {
         if(run=="reload")
         {
            var pages:Array=api.getPages();
            for(var i:int=0;i<pages.length;i++)if(expected.indexOf(pages[i].modId)>=0)
            {
               api.resetPage(i);
               for each(var item:Object in pages[i].items)if(item.kind=="keybind")
               {
                  var current:Object=item["get"](),original:Object=item["def"];
                  ok(current.code==original.code&&current.ctrl==original.ctrl&&current.alt==original.alt&&current.shift==original.shift,
                     pages[i].modId+"/"+item.key+" restores its own default");
               }
            }
         }
         api.closeAll();write(run+"-results.txt",log+"PASS "+checks+" assertions\n");shutdown(0);
      }
      private function shutdown(code:int):void{timer.stop();getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(code);}
   }
}
