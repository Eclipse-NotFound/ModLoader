package
{
   import flash.display.Sprite;
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Loader;
   import flash.display.BitmapData;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.KeyboardEvent;
   import flash.text.TextField;
   import flash.utils.Timer;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   public class LocaleProbe extends Sprite
   {
      private static var probe:LocaleProbe;
      private var main:*,w:*,api:*,net:*;
      private var timer:Timer=new Timer(60);
      private var ticks:int=0,phase:int=0,since:int=0,checks:int=0,languageIndex:int=0,pageIndex:int=0,itemIndex:int=0;
      private var log:String="",samples:Array=[],layouts:Array=[],baseline:Object={};
      private var languages:Array=["zh","en","ru","zh"];
      private var pageIds:Array=["msw","msw-smart","msw-laser","msw-exempt","msw-pointer","sandevistan","realisticvision","rconnect","loot-editor"];
      private var catalogs:Array=[
         ["ModLoaderMod","loader.LoaderLocale"],["MoreSkillsWeaponsMod","msw.MSWLocale"],
         ["SandevistanMod","sandy.SandyLocale"],["RealisticVisionMod","vision.RVLocale"],
         ["RConnectMod","connect.RCLocale"],["RandomRoomsMod","rooms.RRLocale"],
         ["TDFCMod","tactics.TDFCLocale"],["LootEditorMod","loot.LootLocale"]];
      public function LocaleProbe(){trace("LocaleProbe constructed");}
      public static function init(m:*):void
      { trace("LocaleProbe init");probe=new LocaleProbe();probe.main=m;probe.write("heartbeat.txt","init");probe.timer.addEventListener("timer",probe.tick);probe.timer.start(); }
      private function ok(value:Boolean,label:String):void
      { if(!value)throw new Error(label);checks++;log+="PASS "+label+"\n"; }
      private function move(next:int):void { phase=next;since=ticks; }
      private function cls(entry:String,name:String):Class
      {
         var table:*=HostAccess.table(main);
         for(var loader:Object in table)if(table[loader]==entry)
         {var domain:*=Loader(loader).contentLoaderInfo.applicationDomain;if(domain.hasDefinition(name))return domain.getDefinition(name) as Class;}
         return null;
      }
      private function page(id:String):Object {for each(var p:Object in api.getPages())if(p.modId==id)return p;return null;}
      private function find(o:*,name:String):* {
         if(o==null)return null;if(o.name==name)return o;
         if(o is DisplayObjectContainer)for(var i:int=0;i<o.numChildren;i++){var r:*=find(o.getChildAt(i),name);if(r)return r;}return null;
      }
      private function findType(o:*,name:String):* {
         if(o==null)return null;if(getQualifiedClassName(o)==name)return o;
         if(o is DisplayObjectContainer)for(var i:int=0;i<o.numChildren;i++){var r:*=findType(o.getChildAt(i),name);if(r)return r;}return null;
      }
      private function languageButton(o:*,code:String):* {
         if(o is DisplayObjectContainer){var n:*=o.getChildByName("n");if(n is TextField && n.text==code && o.getChildByName("lang"))return o;
            for(var i:int=0;i<o.numChildren;i++){var r:*=languageButton(o.getChildAt(i),code);if(r)return r;}}return null;
      }
      private function click(o:*):void {if(!o)throw new Error("missing click target");o.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));}
      private function key(code:int):void {main.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN,true,false,0,code));main.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP,true,false,0,code));}
      private function fields(o:*,out:Array,onlyVisible:Boolean=true):void {
         if(o==null || (onlyVisible && !o.visible))return;
         if(o is TextField)out.push(o);
         if(o is DisplayObjectContainer)for(var i:int=0;i<o.numChildren;i++)fields(o.getChildAt(i),out,onlyVisible);
      }
      private function inspect(o:*,label:String,fit:Boolean=true):void {
         ok(o!=null,label+" display exists");
         var list:Array=[];fields(o,list);var texts:Array=[];
         for each(var tf:TextField in list){
            texts.push(tf.text);
            if(languages[languageIndex]!="zh")ok(!/[\u3400-\u9fff]/.test(tf.text),label+" no Chinese: "+tf.text);
            if(fit && tf.text.length && tf.autoSize=="none"){
               var overflow:Boolean=tf.textWidth>tf.width+1 || tf.textHeight>tf.height+1;
               if(overflow)layouts.push({label:label,text:tf.text,width:tf.width,textWidth:tf.textWidth,height:tf.height,textHeight:tf.textHeight});
            }
         }
         samples.push({language:languages[languageIndex],label:label,text:texts});
      }
      private function nativeCatalog():* {return getDefinitionByName("fe.Res")["d"];}
      private function inspectHelp(label:String):void {
         var panel:*=find(main,"ModSettingsNavigation").parent;
         for(var i:int=0;i<panel.numChildren;i++){
            var field:*=panel.getChildAt(i);
            if(field is TextField && field.visible && field.x==600)inspect(field,label+" help");
         }
      }
      private function switchLanguage():void {
         if(api.isOpen())click(find(main,"ModSettingsButton"));
         w.pip.onoff(-1);var button:*=languageButton(main,languages[languageIndex]);
         ok(button!=null,"native language button exists "+languages[languageIndex]);click(button);move(3);
      }
      private function tick(e:Event):void {
         try {
            ticks++;if(ticks%50==0)write("heartbeat.txt","phase="+phase+" ticks="+ticks+" checks="+checks);
            if(ticks>2800)throw new Error("probe timeout phase="+phase);
            w=getDefinitionByName("fe.World")["w"];if(!w)return;
            if(w.verror && w.verror.visible)throw new Error("native dialog: "+w.verror.txt.text);
            var carrier:*=main.getChildByName("ModSettingsCarrier");if(!carrier)return;api=carrier.modAPI;
            if(phase==0){
               if(!w.allLandsLoaded)return;for each(var id:String in pageIds)if(!page(id))return;
               for each(var spec:Array in catalogs){
                  var locale:Class=cls(spec[0],"modlocales."+spec[1]);if(!locale)return;
                  var data:Object=cls(spec[0],"modlocales."+spec[1]+"Messages")["DATA"];
                  for(var source:String in data){
                     for each(var code:String in ["en","ru"]){
                        var translated:String=locale["translate"](source,code);
                        ok(translated==data[source][code] && translated.length>0 && !/[\u3400-\u9fff]/.test(translated),spec[0]+" catalog "+code+" "+source);
                     }
                     ok(locale["translate"](source,"tw")==locale["translate"](source,"zh"),spec[0]+" Traditional Chinese fallback");
                     ok(locale["translate"](source,"de")==data[source].en,spec[0]+" other language fallback");
                  }
               }
               ok(api.getPages().length==9,"nine pages, no duplicate registration");
               ok(api.localizationVersion==1,"localizationVersion=1 release marker");
               for each(var p:Object in api.getPages())for each(var it:Object in p.items)baseline[p.modId+"/"+it.key]=it.get();
               net=findType(main.stage,"rconnect.ui::NetHud");ok(net!=null,"production RConnect HUD");
               net.tfNick.text="Pilot开Ж{1}";net.chatLog.text="User关: Hello Привет 中文 {0}";
               w.mm.active=false;w.newGame(-1,"LP",null);move(1);return;
            }
            if(phase==1){if(!w.gg || !w.loc || w.allStat!=1)return;if(ticks-since<110)return;switchLanguage();return;}
            if(phase==3 && ticks-since>24){
               ok(w.lang==languages[languageIndex],"native switch selected "+w.lang);
               ok(net.tfNick.text=="Pilot开Ж{1}" && net.chatLog.text=="User关: Hello Привет 中文 {0}","player nickname and chat preserved");
               var safeText:String="模组 开 中文 Привет {0}";
               var hostLocale:Class=cls("ModLoaderMod","modlocales.loader.LoaderLocale"),safeField:TextField=new TextField();
               hostLocale["bind"](safeField,safeText,false,true);
               ok(safeField.text==safeText,"host preserves client-rendered player text");
               net.visible=false;w.pip.onoff(5);move(8);return;
            }
            if(phase==8 && ticks-since>7){
               click(find(main,"ModSettingsButton"));pageIndex=0;itemIndex=0;ok(api.selectPage(pageIds[pageIndex]),"first settings page opens");move(4);return;
            }
            if(phase==4 && ticks-since>7){
               p=page(pageIds[pageIndex]);var prefix:String=languages[languageIndex]+"/"+p.modId;
               var translatedName:String=api.text(p,p.displayName);
               if(w.lang!="zh")ok(!/[\u3400-\u9fff]/.test(translatedName+api.text(p,p.desc)),prefix+" title and description");
               for each(it in p.items){
                  if(w.lang!="zh")ok(!/[\u3400-\u9fff]/.test(api.text(p,it.label)+api.text(p,it.hint)+api.text(p,it.suffix)),prefix+" item "+it.key);
               }
               inspect(find(main,"ModSettingsNavigation"),prefix+" navigation",false);
               inspectHelp(prefix);
               for each(it in p.items){var row:*=find(main,"SettingsItem:"+it.key);if(row && row.visible){inspect(row,prefix+"/"+it.key);row.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_OVER,true));}}
               if(p.modId=="msw-exempt"){
                  for each(var group:Object in p.groups){
                     var expand:*=find(main,"SettingsGroupExpand:"+group.id);if(!expand.settingsExpanded)click(expand);
                     inspect(find(main,"SettingsGroup:"+group.id),prefix+" group");
                     for each(it in group.items){row=find(main,"SettingsItem:"+it.key);ok(row!=null,prefix+" expanded "+it.key);inspect(row,prefix+"/"+it.key);}
                  }
               }
               inspectHelp(prefix+" hovered");
               screenshot(prefix.replace("/","-")+(itemIndex?"-"+itemIndex:"")+".png");
               var nextItems:*=find(main,"SettingsNextItems");
               if(nextItems.mouseEnabled){click(nextItems);itemIndex++;move(4);return;}
               pageIndex++;itemIndex=0;if(pageIndex<pageIds.length){api.selectPage(pageIds[pageIndex]);move(4);return;}
               click(find(main,"ModSettingsButton"));w.pip.onoff(-1);key(117);move(5);return;
            }
            if(phase==5 && ticks-since>7){
               inspect(find(main,"MSWF6Panel"),w.lang+" F6",false);screenshot(w.lang+"-f6.png");key(117);
               net.visible=true;net.refresh();
               var sourceNick:String=net.tfNick.text,sourceChat:String=net.chatLog.text;
               // Inputs/chat are intentionally not translated; only inspect labels/buttons.
               for(var ni:int=0;ni<net.numChildren;ni++){var child:*=net.getChildAt(ni);if(child!==net.tfNick && child!==net.tfIp && child!==net.tfPort && child!==net.tfChat && child!==net.chatLog)inspect(child,w.lang+" network");}
               screenshot(w.lang+"-network.png");net.visible=false;
               var root:*=find(main.stage,"TDFC_DebugRoot");click(root.getChildAt(1));move(6);return;
            }
            if(phase==6 && ticks-since>7){
               inspect(find(main.stage,"TDFC_DebugRoot"),w.lang+" tactics");screenshot(w.lang+"-tactics.png");click(find(main.stage,"TDFC_DebugRoot").getChildAt(1));
               w.gg.ggControl=true;key(112);move(7);return;
            }
            if(phase==7 && ticks-since>7){
               var picker:*=findType(main.stage,"rr::RRScenePicker");ok(picker!=null,"native F1 opens production scene picker");
               inspect(picker,w.lang+" scene picker");screenshot(w.lang+"-rooms.png");key(27);
               var res:*=getDefinitionByName("fe.Res"),ml:Class=cls("MoreSkillsWeaponsMod","modlocales.msw.MSWLocale");
               for each(var wp:Array in [["mswglau","可编程榴弹炮"],["mswdazzler","非致命激光枪"],["mswlaserpointer","激光笔"]])
                  ok(res["txt"]("w",wp[0])==ml["text"](wp[1]),w.lang+" native weapon name "+wp[0]);
               var scene:Class=cls("RandomRoomsMod","rr.RRScene");scene["configureLand"](w,{id:"random_rooms"},"plant","13");
               var rr:Class=cls("RandomRoomsMod","modlocales.rooms.RRLocale");
               ok(String(nativeCatalog().map.(@id=="random_rooms").n).indexOf(rr["text"]("工厂"))==0,w.lang+" native map title");
               languageIndex++;if(languageIndex<languages.length){switchLanguage();return;}
               for each(p in api.getPages())for each(it in p.items)ok(it.get()===baseline[p.modId+"/"+it.key],"language switch keeps setting "+p.modId+"/"+it.key);
               write("samples.json",JSON.stringify(samples));write("layout.json",JSON.stringify(layouts));
               ok(layouts.length==0,"no clipped localized fields (see layout.json)");
               write("results.txt",log+"PASS "+checks+" checks\n");timer.stop();getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(0);
            }
         }catch(error:*){write("results.txt",log+"FAIL phase="+phase+" "+error+"\n"+(error is Error?error.getStackTrace():""));write("samples.json",JSON.stringify(samples));write("layout.json",JSON.stringify(layouts));screenshot("failure.png");timer.stop();getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(1);}
      }
      private function write(name:String,text:String):void {var F:Class=getDefinitionByName("flash.filesystem.File") as Class,S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class,fs:*=new S();fs.open(F["applicationStorageDirectory"].resolvePath(name),"write");fs.writeUTFBytes(text);fs.close();}
      private function screenshot(name:String):void {var b:BitmapData=new BitmapData(main.stage.stageWidth,main.stage.stageHeight,false,0);b.draw(main.stage);var F:Class=getDefinitionByName("flash.filesystem.File") as Class,S:Class=getDefinitionByName("flash.filesystem.FileStream") as Class,E:Class=getDefinitionByName("flash.display.PNGEncoderOptions") as Class,fs:*=new S();fs.open(F["applicationStorageDirectory"].resolvePath(name),"write");fs.writeBytes(Object(b)["encode"](b.rect,new E()));fs.close();b.dispose();}
   }
}
