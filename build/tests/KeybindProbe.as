package
{
   import flash.display.Sprite;
   import flash.display.BitmapData;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.net.SharedObject;
   import flash.utils.Timer;
   import flash.utils.getDefinitionByName;

   /** Exercises the real menu, event propagation and a fresh process reload. */
   public class KeybindProbe extends Sprite
   {
      private static var self:KeybindProbe;
      private var main:*, w:*, api:*;
      private var timer:Timer = new Timer(50);
      private var ticks:int, phase:int, since:int, checks:int;
      private var log:String = "", run:String;
      private var cell:Object;
      private var preferences:SharedObject;
      private var nativeDowns:int = 0;
      private var priorReleases:int = 0;
      private var originalCell:Object;

      public function KeybindProbe() {}
      public static function init(m:*):void
      {
         self = new KeybindProbe(); self.main = m;
         self.run = self.readApp("scenario.txt").split(":")[1];
         self.preferences = SharedObject.getLocal("KeybindProbe", "/");
         self.cell = self.preferences.data.binding == null ? {code:121,ctrl:false,alt:false,shift:false} : self.preferences.data.binding;
         self.timer.addEventListener("timer",self.tick); self.timer.start();
      }
      private function ok(value:Boolean,label:String):void
      {
         if(!value) throw new Error(label);
         checks++; log += "PASS " + label + "\n";
      }
      private function advance(value:int):void {phase = value; since = ticks;}
      private function fixture():void
      {
         var owner:KeybindProbe = this;
         api.registerPage("keybind-fixture","改键验证",[
            {key:"action",label:"测试动作",kind:"keybind",def:{code:121,ctrl:false,alt:false,shift:false},
               get:function():* {return owner.cell;},set:function(v:*):void {owner.cell=v;owner.preferences.data.binding=v;owner.preferences.flush();}},
            {key:"legacy",label:"旧开关",kind:"check",def:false,get:function():* {return false;},set:function(v:*):void {}}
         ],null,"点击当前按键进行修改。",{moduleId:"keybind-fixture",moduleName:"改键验证",featureName:"快捷键"});
         api.registerPage("keybind-other","冲突验证",[
            {key:"other",label:"另一个动作",kind:"keybind",get:function():* {return {code:121,ctrl:false,alt:false,shift:false};},set:function(v:*):void {}}
         ]);
      }
      private function event(code:int,down:Boolean=true,ctrl:Boolean=false,alt:Boolean=false,shift:Boolean=false):KeyboardEvent
      {return new KeyboardEvent(down?KeyboardEvent.KEY_DOWN:KeyboardEvent.KEY_UP,true,true,0,code,0,ctrl,alt,shift);}
      private function press(code:int,ctrl:Boolean=false,alt:Boolean=false,shift:Boolean=false):void
      {main.stage.dispatchEvent(event(code,true,ctrl,alt,shift));main.stage.dispatchEvent(event(code,false,ctrl,alt,shift));}
      private function tick(e:Event):void
      {
         try
         {
            ticks++;
            if(ticks%100==0) write("heartbeat.txt","phase="+phase+" ticks="+ticks+"\n"+log);
            if(ticks>1800) throw new Error("timeout phase="+phase);
            w = getDefinitionByName("fe.World")["w"]; if(w==null)return;
            if(w.verror && w.verror.visible)throw new Error(w.verror.txt.text);
            var c:* = main.getChildByName("ModSettingsCarrier"); if(c==null)return; api=c.modAPI;
            if(phase==0)
            {
               if(!w.allLandsLoaded)return;
               ok(api.keybindVersion==1 && api.apiVersion==1 && api.menuVersion==1,"new capability preserves existing interface versions");
               fixture();
               ok(api.keyConflict("keybind-fixture","action",{code:121,ctrl:false,alt:false,shift:false})!="","existing F10 collision is visible without changing defaults");
               var before:int=api.getPages().length;
               api.registerPage("bad-binding","bad",[{key:"x",kind:"keybind",def:{code:16},get:function():*{return null;},set:function(v:*):void{}}]);
               ok(api.getPages().length==before,"invalid keybind registration cannot publish a broken page");
               w.mm.active=false;w.newGame(-1,"LP",null);advance(1);return;
            }
            if(phase==1)
            {
               if(w.gg==null || w.loc==null || ticks-since<110)return;
               press(121);w.pip.onoff(5);advance(2);return;
            }
            if(phase==2 && ticks-since>6)
            {
               ok(api.selectPage("keybind-fixture"),"new page opens in the real Pip menu");advance(3);return;
            }
            if(phase==3 && ticks-since>4)
            {
               var button:* = find(main,"SettingsKeyChange:action");
               ok(button!=null && button.visible && button.width<=212,"binding uses an actionable menu button within its row");
               ok(find(main,"SettingsKeyClear:action")!=null,"clear binding control is available");
               if(run=="reload")
               {
                  ok(cell.code==75 && cell.ctrl && !cell.alt && !cell.shift,"client binding survives a fresh process");
                  ok(api.matchesKey("keybind-fixture","action",event(75,true,true)),"restored binding drives the shared matcher");
                  api.resetPage(pageIndex("keybind-fixture"));
                  ok(cell.code==121 && !cell.ctrl,"restore defaults restores the original binding");
                  advance(8);return;
               }
               screenshot("keybind-menu.png");
               main.stage.addEventListener(KeyboardEvent.KEY_DOWN,nativeObserver,false,-20000);
               main.stage.addEventListener(KeyboardEvent.KEY_UP,priorReleaseObserver,false,-20000);
               main.stage.dispatchEvent(event(125));
               var baselineDowns:int = nativeDowns;
               button.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
               ok(api.isCapturingKey(),"clicking current binding begins capture");
               main.stage.dispatchEvent(event(125,false));
               ok(priorReleases==1,"a press preceding capture keeps its release for client cleanup");
               main.stage.dispatchEvent(event(17,true,true));
               ok(api.isCapturingKey(),"a modifier alone keeps waiting");
               main.stage.dispatchEvent(event(75,true,true));
               ok(cell.code==75 && cell.ctrl && !api.isCapturingKey(),"new exact Ctrl+K binding reaches the client setter");
               ok(!api.matchesKey("keybind-fixture","action",event(75,true,true)),"new binding cannot fire before the captured press is released");
               main.stage.dispatchEvent(event(75,true,true));
               ok(nativeDowns==baselineDowns,"capture and operating-system repeat do not reach game listeners");
               main.stage.dispatchEvent(event(75,false,true));main.stage.dispatchEvent(event(17,false));
               ok(api.matchesKey("keybind-fixture","action",event(75,true,true)),"binding becomes usable after release");
               ok(!api.matchesKey("keybind-fixture","action",event(75,true,true,false,true)),"extra modifiers do not match");
               api.beginKeyCapture("keybind-fixture","action");press(74);
               ok(api.isCapturingKey() && cell.code==75,"native bare-key collision is rejected without losing the old value");
               api.beginKeyCapture("keybind-fixture","action");press(121);
               ok(api.isCapturingKey() && cell.code==75,"cross-mod collision is rejected before the old F10 listeners");
               screenshot("keybind-conflict.png");
               press(27);ok(!api.isCapturingKey() && cell.code==75,"Escape cancels without replacing the binding");
               api.beginKeyCapture("keybind-fixture","action");press(46);
               ok(cell.code==0 && !api.matchesKey("keybind-fixture","action",event(0)),"Delete clears instead of becoming a gameplay key");
               api.beginKeyCapture("keybind-fixture","action");press(75,true);
               ok(cell.code==75 && cell.ctrl,"an unbound action can be rebound");
               api.beginKeyCapture("keybind-fixture","action");api.selectPage("keybind-other");advance(4);return;
            }
            if(phase==4 && ticks-since>4)
            {
               ok(!api.isCapturingKey(),"changing page cancels capture");
               api.selectPage("keybind-fixture");advance(5);return;
            }
            if(phase==5 && ticks-since>4)
            {
               api.beginKeyCapture("keybind-fixture","action");main.stage.dispatchEvent(new Event(Event.DEACTIVATE));
               ok(!api.isCapturingKey() && !api.isKeyDown("keybind-fixture","action"),"losing focus cancels capture and releases held state");
               api.beginKeyCapture("keybind-fixture","action");api.closeAll();
               ok(!api.isCapturingKey(),"closing all pages cancels capture");
               var index:int=pageIndex("keybind-fixture");api.resetPage(index);
               ok(cell.code==121 && !cell.ctrl,"reset keeps the original default despite an existing conflict");
               api.beginKeyCapture("keybind-fixture","action");press(75,true);
               w.lang="en";advance(6);return;
            }
            if(phase==6 && ticks-since>8)
            {
               ok(textOf(find(main,"SettingsKeyClear:action")).indexOf("Clear")>=0,"new controls follow English language switching");
               screenshot("keybind-english.png");w.lang="ru";advance(7);return;
            }
            if(phase==7 && ticks-since>8)
            {
               ok(textOf(find(main,"SettingsKeyClear:action")).indexOf("Убрать")>=0,"new controls follow Russian language switching");
               screenshot("keybind-russian.png");w.pip.onoff(-1);
               // End this isolated new-character intro before testing gameplay
               // holds. Keep the real sealed GUI and native key processing.
               w.gui.dialScript.running=false;w.gui.guiPause=false;main.stage.focus=null;
               advance(9);return;
            }
            if(phase==8 && ticks-since>4)
            {
               ok(find(main,"SettingsKeyChange:action")!=null,"reset page still renders its binding control");
               finish();return;
            }
            if(phase==9 && ticks-since>4)
            {
               main.stage.dispatchEvent(event(17,true,true));main.stage.dispatchEvent(event(75,true,true));
               ok(api.isKeyDown("keybind-fixture","action"),"held query sees the exact combination during gameplay");
               main.stage.dispatchEvent(event(16,true,true,false,true));
               ok(!api.isKeyDown("keybind-fixture","action"),"held query rejects an extra modifier");
               main.stage.dispatchEvent(event(16,false,true));
               ok(api.isKeyDown("keybind-fixture","action"),"releasing the extra modifier restores the held combination");
               main.stage.dispatchEvent(event(75,false,true));main.stage.dispatchEvent(event(17,false));
               ok(!api.isKeyDown("keybind-fixture","action"),"releasing the primary key ends the held action");
               finish();return;
            }
         }
         catch(error:*) {write(run+"-results.txt",log+"FAIL "+error+"\n"+error.getStackTrace());shutdown(1);}
      }
      private function nativeObserver(e:KeyboardEvent):void {nativeDowns++;}
      private function priorReleaseObserver(e:KeyboardEvent):void {if(e.keyCode==125)priorReleases++;}
      private function pageIndex(id:String):int
      {var p:Array=api.getPages();for(var i:int=0;i<p.length;i++)if(p[i].modId==id)return i;return -1;}
      private function textOf(o:*):String
      {if(o==null)return "";var s:String="text" in o?o.text:"";if("numChildren" in o)for(var i:int=0;i<o.numChildren;i++)s+=textOf(o.getChildAt(i));return s;}
      private function find(o:*,name:String):*
      {if(o==null)return null;if(o.name==name)return o;if("numChildren" in o)for(var i:int=0;i<o.numChildren;i++){var r:*=find(o.getChildAt(i),name);if(r!=null)return r;}return null;}
      private function fileText(f:*):String
      {if(!f.exists)return "";var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;var s:*=new S();s.open(f,"read");var t:String=s.readUTFBytes(s.bytesAvailable);s.close();return t;}
      private function readApp(path:String):String {return fileText(getDefinitionByName("flash.filesystem.File")["applicationDirectory"].resolvePath(path));}
      private function write(name:String,text:String):void
      {var F:Class=getDefinitionByName("flash.filesystem.File") as Class;var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;var s:*=new S();s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeUTFBytes(text);s.close();}
      private function screenshot(name:String):void
      {var st:*=main.stage;var b:BitmapData=new BitmapData(st.stageWidth,st.stageHeight,false,0);b.draw(st);var E:Class=getDefinitionByName("flash.display.PNGEncoderOptions") as Class;var bytes:*=Object(b)["encode"](b.rect,new E());var F:Class=getDefinitionByName("flash.filesystem.File") as Class;var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;var s:*=new S();s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeBytes(bytes);s.close();b.dispose();}
      private function finish():void {api.closeAll();write(run+"-results.txt",log+"PASS "+checks+" assertions\n");shutdown(0);}
      private function shutdown(code:int):void {timer.stop();getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(code);}
   }
}
