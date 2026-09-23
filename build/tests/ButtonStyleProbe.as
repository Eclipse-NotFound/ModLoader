package
{
   import flash.display.Sprite;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.geom.Matrix;
   import flash.text.TextField;
   import flash.utils.Timer;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;

   /** Investigation only. Runs exclusively in a private AIR application. */
   public class ButtonStyleProbe extends Sprite
   {
      private static var probe:ButtonStyleProbe;
      private var main:*, w:*, api:*, ov:*, nativeButton:*, modButton:*, recordText:TextField;
      private var timer:Timer = new Timer(50);
      private var ticks:int = 0, phase:int = 0, since:int = 0;
      private var navigationTarget:int = 1;
      private var navigationBefore:String;
      private var heartbeatBaseline:int=0;
      private var result:Object = {checks:[], phases:{}};
      public function ButtonStyleProbe() {}
      public static function init(m:*):void
      {
         probe = new ButtonStyleProbe(); probe.main = m;
         probe.timer.addEventListener("timer", probe.tick); probe.timer.start();
      }
      private function advance(p:int):void { phase = p; since = ticks; }
      private function check(value:Boolean, label:String):void { result.checks.push({pass:value,label:label}); }
      private function click(b:*):void { b.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true)); }
      private function tick(e:Event):void
      {
         try
         {
            ticks++;
            if(ticks % 100 == 0) write("heartbeat.txt", "ticks=" + ticks + " phase=" + phase);
            if(ticks > 1500) throw new Error("timeout phase=" + phase);
            w = getDefinitionByName("fe.World")["w"];
            if(w == null) return;
            if(w.verror != null && w.verror.visible) throw new Error("game dialog: " + w.verror.txt.text);
            var carrier:* = main.getChildByName("ModSettingsCarrier"); if(carrier == null) return;
            api = carrier.modAPI;
            if(phase == 0)
            {
               if(!w.allLandsLoaded) return;
               api.registerPage("button-audit", "按钮检查", [{key:"a",label:"这是模组设置",kind:"check",def:true,get:function():Boolean{return true;},set:function(v:*):void{}}], null, "隔离测试");
               w.defuxLang("zh"); advance(1); return;
            }
            if(phase == 1 && w.textLoaded)
            {
               w.pip.updateLang(); w.mm.active = false; w.newGame(-1, "LP", null); advance(2); return;
            }
            if(phase == 2)
            {
               if(w.gg == null || w.loc == null || ticks - since < 110) return;
               w.log = "[BUTTON-AUDIT] 记录页叠加检查\n第二行记录内容";
               w.pip.onoff(5); advance(3); return;
            }
            if(phase == 3 && ticks - since > 6)
            {
               modButton = find(main, "ModSettingsButton");
               if(modButton == null) throw new Error("missing mod button");
               ov = modButton.parent; nativeButton = ov.getChildByName("but5");
               result.language = w.lang; result.nativeClass = getQualifiedClassName(nativeButton);
               result.native = display(nativeButton, 2); result.custom = display(modButton, 3);
               result.nativeText = textProps(nativeButton.text); result.customText = textProps(firstText(modButton));
               var C:Class = getDefinitionByName(getQualifiedClassName(nativeButton)) as Class;
               try { var clone:* = new C(); result.clone = display(clone, 2); } catch(cloneError:*) { result.clone = String(cloneError); }
               result.phases.initial = display(ov, 2);
               click(nativeButton); advance(4); return;
            }
            if(phase == 4 && ticks - since > 4)
            {
               recordText = textContaining(ov, "[BUTTON-AUDIT]");
               check(recordText != null && shown(recordText), "record page displays unique log marker before switching");
               result.record = recordText == null ? null : {text:textProps(recordText),parent:display(recordText.parent,1)};
               screenshot("01-record.png"); result.phases.record = display(ov,2);
               click(modButton); advance(5); return;
            }
            if(phase == 5 && ticks - since > 4)
            {
               check(api.isOpen(), "mod button opens settings");
               check(recordText != null && !shown(recordText), "record text is hidden while mod settings are open");
               result.phases.modAfterRecord = display(ov,2); screenshot("02-mod-after-record.png");
               compareStyles();
               click(modButton); advance(6); return;
            }
            if(phase == 6 && ticks - since > 4)
            {
               check(!api.isOpen() && shown(recordText), "toggle close restores suspended record page");
               check(nativeButton.currentFrame == 2, "toggle close restores native selected tab highlight");
               click(modButton); advance(7); return;
            }
            if(phase == 7 && ticks - since > 4)
            {
               check(!shown(recordText), "record text stays hidden after repeated opening");
               click(ov.getChildByName("but3")); advance(8); return;
            }
            if(phase == 8 && ticks - since > 4)
            {
               check(!api.isOpen(), "native options closes mod settings");
               check(!shown(recordText), "record text stays hidden after switching from mods to options");
               check(ov.getChildByName("but3").currentFrame == 2 && nativeButton.currentFrame == 1, "native navigation keeps the target highlight");
               result.phases.optionsAfterMod = display(ov,2); screenshot("03-options-after-mod.png");
               click(ov.getChildByName("but1")); advance(9); return;
            }
            if(phase == 9 && ticks - since > 4)
            {
               navigationBefore=visibleTextSnapshot(ov);
               click(modButton); advance(10); return;
            }
            if(phase == 10 && ticks - since > 4)
            {
               check(api.isOpen() && !shown(recordText), "native page " + navigationTarget + " is suspended for mods");
               click(ov.getChildByName("but" + navigationTarget)); advance(11); return;
            }
            if(phase == 11 && ticks - since > 4)
            {
               check(!api.isOpen() && navigationBefore == visibleTextSnapshot(ov), "native page " + navigationTarget + " restores exactly its original visible text");
               navigationTarget++;
               if(navigationTarget<=5){click(ov.getChildByName("but"+navigationTarget));advance(9);return;}
               check(shown(recordText), "record can be reopened with its contents intact");
               heartbeatBaseline=lastHeartbeat(readHostLog());
               advance(12); return;
            }
            if(phase == 12 && ticks - since > 20 && ticks % 20 == 0)
            {
               var hostLog:String=readHostLog();
               if(lastHeartbeat(hostLog)<=heartbeatBaseline)return;
               check(hostLog.indexOf("lastErr=")<0, "no runtime UI errors");
               check(/frames=(600|[7-9]\d\d|\d{4,})/.test(hostLog), "host heartbeat continues after navigation tests");
               finish();
            }
         }
         catch(err:*) { result.error = String(err); result.stack = err.getStackTrace(); finish(); }
      }
      private function readHostLog():String
      {
         var file:*=getDefinitionByName("flash.filesystem.File")["applicationStorageDirectory"].resolvePath("ModSettings.log");
         var S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class,s:*=new S();
         s.open(file,"read");var value:String=s.readUTFBytes(s.bytesAvailable);s.close();return value;
      }
      private function lastHeartbeat(text:String):int
      {
         var re:RegExp=/frames=(\d+)/g,m:Object,value:int=0;
         while((m=re.exec(text))!=null)value=Math.max(value,int(m[1]));return value;
      }
      private function compareStyles():void
      {
         var nt:TextField = nativeButton.text, mt:TextField = firstText(modButton);
         var original:String = nt.text; var frame:int = nativeButton.currentFrame;
         nt.text = mt.text;
         var bw:int = Math.ceil(nativeButton.width), bh:int = Math.ceil(nativeButton.height);
         var a:BitmapData = new BitmapData(bw,bh,true,0), b:BitmapData = new BitmapData(bw,bh,true,0);
         a.draw(nt,nt.transform.matrix); b.draw(mt,mt.transform.matrix);
         result.sameLabelNative = textProps(nt); result.sameLabelCustom = textProps(mt);
         result.textPixels = {diff:difference(a,b),nativeInk:String(a.getColorBoundsRect(0xFF000000,0,false)),customInk:String(b.getColorBoundsRect(0xFF000000,0,false))};
         check(result.textPixels.diff == 0, "identical label has identical native text pixels and placement");
         png(a,"text-native.png"); png(b,"text-custom.png");
         nt.text = ""; mt.visible = false;
         nativeButton.gotoAndStop(2); a.fillRect(a.rect,0); a.draw(nativeButton);
         b.fillRect(b.rect,0); b.draw(modButton);
         result.selectedBackground = {diff:difference(a,b)};
         check(result.selectedBackground.diff == 0, "selected background matches native selected frame");
         png(a,"background-native.png"); png(b,"background-custom.png");
         nativeButton.gotoAndStop(frame); nt.text = original; mt.visible = true;
         a.dispose(); b.dispose();
      }
      private function difference(a:BitmapData,b:BitmapData):int
      {
         var n:int = 0; for(var y:int=0;y<a.height;y++) for(var x:int=0;x<a.width;x++) if(a.getPixel32(x,y)!=b.getPixel32(x,y)) n++; return n;
      }
      private function visibleTextSnapshot(d:*):String
      {
         if(d==null || !shown(d)) return "";
         if(d is TextField) return d.name+":"+d.text+"\n";
         var value:String="";if("numChildren" in d)for(var i:int=0;i<d.numChildren;i++)value+=visibleTextSnapshot(d.getChildAt(i));
         return value;
      }
      private function textProps(t:TextField):Object
      {
         if(t == null) return null;
         var o:Object = {}; var keys:Array = ["text","x","y","width","height","scaleX","scaleY","textWidth","textHeight","embedFonts","antiAliasType","gridFitType","sharpness","thickness","autoSize","wordWrap","multiline","textColor","visible","alpha"];
         for each(var k:String in keys) o[k] = t[k];
         var format:Object = {}; var f:* = t.getTextFormat();
         for each(k in ["font","size","color","bold","italic","underline","align","leftMargin","rightMargin","indent","leading","kerning","letterSpacing"]) format[k] = f[k];
         o.format = format; o.matrix = String(t.transform.matrix); o.colorTransform = String(t.transform.colorTransform);
         o.filters = filterProps(t); o.html = t.htmlText; o.styleSheet = t.styleSheet != null;
         try { var l:* = t.getLineMetrics(0); o.line = {ascent:l.ascent,descent:l.descent,leading:l.leading,height:l.height,width:l.width,x:l.x}; } catch(ignore:*) {}
         return o;
      }
      private function filterProps(d:*):Array
      {
         var a:Array=[]; for each(var f:* in d.filters) { var o:Object={type:getQualifiedClassName(f)}; for each(var p:String in ["color","alpha","blurX","blurY","strength","quality","inner","knockout"]) try{o[p]=f[p];}catch(ignore:*){} a.push(o); } return a;
      }
      private function display(d:*, depth:int):Object
      {
         if(d == null) return null;
         var o:Object={name:d.name,type:getQualifiedClassName(d),x:d.x,y:d.y,width:d.width,height:d.height,visible:d.visible,alpha:d.alpha,scaleX:d.scaleX,scaleY:d.scaleY,matrix:String(d.transform.matrix),colorTransform:String(d.transform.colorTransform),filters:filterProps(d)};
         if(d is TextField) {o.text=d.text; o.shown=shown(d);}
         try{o.frame=d.currentFrame;}catch(ignore:*){}
         if(depth>0 && "numChildren" in d){o.children=[];for(var i:int=0;i<d.numChildren;i++)o.children.push(display(d.getChildAt(i),depth-1));}return o;
      }
      private function firstText(d:*):TextField
      {
         if(d == null) return null;
         if(d is TextField) return d;
         if("numChildren" in d) for(var i:int=0;i<d.numChildren;i++){var t:TextField=firstText(d.getChildAt(i));if(t!=null)return t;}return null;
      }
      private function textContaining(d:*,needle:String):TextField
      {
         if(d == null) return null;
         if(d is TextField && d.text.indexOf(needle)>=0) return d;
         if("numChildren" in d) for(var i:int=0;i<d.numChildren;i++){var t:TextField=textContaining(d.getChildAt(i),needle);if(t!=null)return t;}return null;
      }
      private function shown(d:*):Boolean { if(d == null)return false; while(d != null){if(!d.visible || d.alpha==0)return false;d=d.parent;}return true; }
      private function find(d:*,name:String):* { if(d==null)return null;if(d.name==name)return d;if("numChildren" in d)for(var i:int=0;i<d.numChildren;i++){var r:*=find(d.getChildAt(i),name);if(r!=null)return r;}return null; }
      private function write(name:String,value:String):void
      {
         var F:Class=getDefinitionByName("flash.filesystem.File") as Class, S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;
         var s:*=new S();s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeUTFBytes(value);s.close();
      }
      private function png(b:BitmapData,name:String):void
      {
         var E:Class=getDefinitionByName("flash.display.PNGEncoderOptions") as Class, F:Class=getDefinitionByName("flash.filesystem.File") as Class, S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class;
         var s:*=new S();s.open(F["applicationStorageDirectory"].resolvePath(name),"write");s.writeBytes(Object(b)["encode"](b.rect,new E()));s.close();
      }
      private function screenshot(name:String):void { var b:BitmapData=new BitmapData(main.stage.stageWidth,main.stage.stageHeight,false,0);b.draw(main.stage);png(b,name);b.dispose(); }
      private function finish():void
      {
         timer.stop();write("result.json",JSON.stringify(result,null,2));
         var failed:int=result.error?1:0;var lines:Array=[];for each(var c:Object in result.checks){lines.push((c.pass?"PASS ":"FAIL ")+c.label);if(!c.pass)failed++;}
         if(result.error)lines.push("ERROR "+result.error);lines.push("failures="+failed);write("results.txt",lines.join("\n"));
         getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(failed == 0?0:1);
      }
   }
}
