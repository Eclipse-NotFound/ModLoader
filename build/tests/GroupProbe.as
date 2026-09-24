package
{
   import flash.display.Sprite;
   import flash.display.BitmapData;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.KeyboardEvent;
   import flash.utils.getDefinitionByName;
   import flash.utils.Timer;

   /** Black-box menu contract checks against the candidate SWFs in a private game. */
   public class GroupProbe extends Sprite
   {
      private static var probe:GroupProbe;
      private var main:*;
      private var w:*;
      private var api:*;
      private var timer:Timer = new Timer(50);
      private var ticks:int = 0;
      private var phase:int = 0;
      private var since:int = 0;
      private var checks:int = 0;
      private var log:String = "";
      private var scenario:String;
      private var run:String;
      private var closed:int = 0;
      private var fixtures:Array = [];

      public function GroupProbe() {}
      public static function init(m:*):void
      {
         probe = new GroupProbe(); probe.main = m;
         var parts:Array = probe.readApp("scenario.txt").split(":");
         probe.scenario = parts[0]; probe.run = parts.length > 1 ? parts[1] : "first";
         probe.timer.addEventListener("timer", probe.tick); probe.timer.start();
      }
      private function ok(value:Boolean, label:String):void
      {
         if(!value) throw new Error(label);
         checks++; log += "PASS " + label + "\n";
      }
      private function advance(value:int):void { phase = value; since = ticks; }
      private function page(id:String):*
      {
         for each(var p:Object in api.getPages()) if(p.modId == id) return p;
         return null;
      }
      private function item(id:String, key:String):*
      {
         for each(var it:Object in page(id).items) if(it.key == key) return it;
         throw new Error("Missing item " + id + "/" + key);
      }
      private function nav():* { return find(main, "ModSettingsNavigation"); }
      private function current(id:String):Boolean { return nav() != null && nav().pageId == id && api.isOpen(); }
      private function click(name:String):void
      {
         var target:* = find(main, name);
         if(target == null || !target.mouseEnabled) throw new Error("Unavailable button " + name);
         target.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true));
      }
      private function f6():void
      {
         main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, false, 0, 117));
         main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP, true, false, 0, 117));
      }
      private function fixture(id:String, count:int, moduleId:String, feature:String, order:int):void
      {
         var items:Array = [];
         for(var i:int = 0; i < count; i++)
         {
            var cell:Object = {value:true}; fixtures.push(cell);
            items.push(fixtureItem(cell, id + "/" + i));
         }
         api.registerPage(id, id, items, function():void { closed++; }, "Menu test fixture",
            {moduleId:moduleId, moduleName:moduleId, featureName:feature, featureOrder:order});
      }
      private function fixtureItem(cell:Object, key:String):Object
      {
         return {key:key, label:key, kind:"check", def:false,
            get:function():Boolean { return cell.value; }, set:function(v:*):void { cell.value = v; }};
      }
      private function countOn(group:Object):int
      { var n:int=0; for each(var it:Object in group.items) if(it.get()===true)n++;return n; }
      private function expanded(id:String):Boolean
      { var button:*=find(main,"SettingsGroupExpand:"+id);return button!=null && button.settingsExpanded; }
      private function stateLabel(id:String):String
      { return String(find(main,"SettingsGroupToggle:"+id).settingsLabel); }
      private function toggleItem(key:String,value:Boolean):void
      {
         var row:*=find(main,"SettingsItem:"+key);ok(row!=null,"visible child "+key);
         row.settingsSc.selected=value;row.settingsSc.dispatchEvent(new Event("change"));
      }
      private function assertions():void
      {
         var p:Object=page("msw-exempt"),groups:Array=p.groups;
         ok(api.apiVersion==1 && api.menuVersion==1 && api.groupVersion==1,"additive capability preserves APIs");
         ok(p.items.length==31 && groups.length==5,"five groups retain all 31 flat items");
         ok(rows().length==0,"first opening starts collapsed");
         for each(var g:Object in groups)ok(!expanded(g.id),"initially collapsed "+g.id);
         ok(stateLabel("bio").indexOf("部分豁免（1/9）")>=0,"existing partial choices shown in header");
         click("SettingsGroupExpand:bio");
         ok(rows().length==9 && expanded("bio") && item("msw-exempt","smartExclude_rat").get(),"expand does not alter existing choice");
         checkGeometry();screenshot("groups-partial.png");
         click("SettingsGroupToggle:bio");
         ok(countOn(groups[0])==9 && stateLabel("bio").indexOf("全部豁免（9/9）")>=0,"partial click fills group");
         for each(var row:* in rows())ok(row.settingsSc.selected===true,"bulk action updates checkbox "+row.settingsItem.key);
         ok(countOn(groups[3])==1 && countOn(groups[4])==1,"bulk action leaves sibling groups alone");
         click("SettingsGroupToggle:bio");ok(countOn(groups[0])==0,"full group click clears it");
         toggleItem("smartExclude_fish",true);
         ok(stateLabel("bio").indexOf("部分豁免（1/9）")>=0,"individual toggle refreshes aggregate immediately");
         click("SettingsGroupExpand:devices");
         ok(!expanded("bio") && expanded("devices") && rows().length==8,"only one group opens at a time");
         toggleItem("smartExclude_transmitter",false);
         ok(stateLabel("devices").indexOf("未豁免（0/8）")>=0,"last child off shows none");
         click("SettingsGroupToggle:devices");ok(countOn(groups[4])==8,"none click fills whole group");
         ok(item("msw-exempt","smartExclude_transmitter").get()===true && item("msw-exempt","smartExclude_fish").get()===true && item("msw-exempt","smartExclude_rat").get()===false,"batch and individual choices share existing callbacks");
         api.selectPage("msw-smart");api.selectPage("msw-exempt");ok(expanded("devices"),"feature switch retains expansion");
         click("ModSettingsButton");click("ModSettingsButton");ok(expanded("devices"),"menu close reopen retains expansion");
         for each(g in groups)g.setAll(true);
         click("SettingsReset");
         var allOff:Boolean=true;for each(var it:Object in p.items)if(it.get())allOff=false;
         ok(allOff && expanded("devices"),"reset includes collapsed children and keeps expanded group");
         for each(g in groups)ok(stateLabel(g.id).indexOf("（0/"+g.items.length+"）")>=0,"reset updates header "+g.id);
         screenshot("groups-devices.png");
         genericChecks();
         api.selectPage("msw-exempt");
         click("SettingsGroupExpand:bio");
         toggleItem("smartExclude_rat",true);
         ok(rows().length==9,"largest category fits without content paging");
         ok(!find(main,"SettingsNextItems").mouseEnabled,"MSW grouped page needs no pagination");
         var headers:int=0;for each(g in groups){var h:*=find(main,"SettingsGroup:"+g.id);ok(h!=null && h.y>=160 && h.y+h.height<=610,"header geometry "+g.id);headers++;}
         ok(headers+rows().length==14,"largest expansion occupies fourteen rows");screenshot("groups-bio.png");
      }
      private function genericChecks():void
      {
         fixture("group-fixture",40,"group-fixture","",0);
         var p:Object=page("group-fixture"),keys:Array=[];
         for each(var it:Object in p.items)keys.push(it.key);
         api.registerPage(p.modId,p.displayName,p.items,p.onPageClose,p.desc,{groups:[{id:"long",label:"长分组",keys:keys}]});
         api.selectPage(p.modId);ok(rows().length==0,"generic read-only header supports folded items");
         click("SettingsGroupExpand:long");ok(rows().length==15,"group header participates in row capacity");
         click("SettingsNextItems");ok(rows().length==16,"long group continues on next page");
         click("SettingsNextItems");ok(rows().length==9,"long group last children remain reachable");checkGeometry();
         var rev:uint=api.revision;
         api.registerPage(p.modId,"bad",p.items,null,"",{groups:[{id:"bad",keys:[keys[0],keys[0]]}]});
         ok(api.revision==rev && p.groups[0].id=="long","duplicate group item rejected atomically");
         api.registerPage(p.modId,"bad",p.items,null,"",{groups:[{id:"bad",keys:["absent"]}]});
         ok(api.revision==rev,"missing group item rejected");
         api.registerPage(p.modId,p.displayName,p.items,p.onPageClose,p.desc);
         ok(p.groups.length==1 && p.groups[0].items[0]===p.items[0],"legacy refresh keeps groups and original item identity");
         var state:Object={v:5};
         var slider:Object={key:"range",label:"范围",kind:"slider",min:0,max:10,step:1,def:2,get:function():Number{return state.v;},set:function(v:*):void{state.v=Number(v);}};
         api.registerPage("group-slider","通用滑杆",[slider],null,"",{groups:[{id:"range",label:"滑杆组",keys:["range"]}]});
         api.selectPage("group-slider");click("SettingsGroupExpand:range");ok(rows().length==1 && rows()[0].settingsItem===slider,"fold-only groups accept existing sliders");
         click("SettingsReset");ok(state.v==2,"grouped slider retains default reset");
         // Remember an absent group's ID without overwriting it on temporary removal.
         api.selectPage("group-fixture");
         api.registerPage(p.modId,p.displayName,p.items,null,"",{groups:[]});
         api.selectPage("group-slider");api.selectPage(p.modId);
         var so:*=getDefinitionByName("flash.net.SharedObject")["getLocal"]("ModSettingsMenu","/");
         ok(so.data.expandedGroups["$group-fixture"]=="long","temporarily missing group preserves expansion intent");
         api.registerPage(p.modId,p.displayName,p.items,null,"",{groups:[{id:"long",keys:keys}]});
         api.selectPage(p.modId);ok(expanded("long"),"late group restores remembered expansion");
      }
      private function tick(e:Event):void
      {
         try {
            ticks++;if(ticks%100==0)write("heartbeat.txt","ticks="+ticks+" phase="+phase+"\n"+log);
            if(ticks>2600)throw new Error("timeout phase="+phase);
            w=getDefinitionByName("fe.World")["w"];if(w==null)return;
            if(w.verror!=null && w.verror.visible)throw new Error("game dialog: "+w.verror.txt.text);
            var carrier:*=main.getChildByName("ModSettingsCarrier");if(carrier==null)return;api=carrier.modAPI;
            if(phase==0) {
               if(page("msw-exempt")==null || page("msw-pointer")==null || page("sandevistan")==null
                  || page("realisticvision")==null || page("rconnect")==null || !w.allLandsLoaded)return;
               ok(countName(main,"ModSettingsCarrier")==1,"single settings carrier");
               ok(api.getPages().length==8,"all current client pages register once");
               if(run=="first" || run=="smoke") {
                  item("msw-exempt","smartExclude_rat").set(true);
                  item("msw-exempt","smartExclude_mine").set(true);
                  item("msw-exempt","smartExclude_transmitter").set(true);
               }
               w.mm.active=false;w.newGame(-1,"LP",null);advance(1);return;
            }
            if(phase==1) {
               if(w.gg==null || w.loc==null || ticks-since<110)return;
               main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN,true,false,0,121));
               main.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP,true,false,0,121));
               w.pip.onoff(5);advance(2);return;
            }
            if(phase==2 && ticks-since>6) {
               click("ModSettingsButton");api.selectPage("msw-exempt");
               if(!("groupVersion" in api)) {
                  ok(rows().length==16 && page("msw-exempt").items.length==31,"new client falls back to flat items on old host");
                  ok(find(main,"SettingsGroup:bio")==null,"old host receives no unsupported groups");
                  f6();ok(!api.isOpen(),"old host F6 still closes");f6();ok(api.isOpen(),"old host F6 still opens");advance(3);return;
               }
               ok(carrier.hostVersion=="2.3.0","new runtime version");
               if(run=="reload") {
                  ok(expanded("bio") && rows().length==9,"expanded group restored across process restart");
                  ok(item("msw-exempt","smartExclude_rat").get()===true && item("msw-exempt","smartExclude_mine").get()===false,"persisted choices survive restart");
                  click("SettingsGroupExpand:bio");ok(rows().length==0,"all groups can be collapsed");finish();return;
               }
               if(run=="final") {ok(rows().length==0 && !expanded("bio"),"explicit all-collapsed state persists across restart");finish();return;}
               assertions();advance(3);return;
            }
            if(phase==3 && ticks-since>10) {
               var text:String=fileText(getDefinitionByName("flash.filesystem.File")["applicationStorageDirectory"].resolvePath("ModSettings.log"));
               if(run!="smoke" || /frames=(600|1200|1800)/.test(text)){finish();return;}
            }
         } catch(err:*) {write(run+"-results.txt",log+"FAIL "+err+"\n"+err.getStackTrace());shutdown(1);}
      }
      private function tabIds(features:Boolean):Array
      {
         var prefix:String = features ? "SettingsFeatureTab:" : "SettingsModuleTab:"; var ids:Array = [];
         for(var i:int = 0; i < nav().numChildren; i++)
         { var child:* = nav().getChildAt(i); if(child.name.indexOf(prefix) == 0) ids.push(child.name.substr(prefix.length)); }
         return ids;
      }
      private function checkBlankFeatures():void
      {
         var blank:Boolean = true;
         for(var i:int = 0; i < nav().numChildren; i++)
         { var child:* = nav().getChildAt(i); if(child.y >= 30 && child.y < 60) blank = false; }
         ok(blank, "unclassified module reserves an empty second row");
      }
      private function checkGeometry():void
      {
         var valid:Boolean = true;
         for each(var row:* in rows())
         {
            if(row.settingsSc != null && "drawNow" in row.settingsSc) row.settingsSc.drawNow();
            if(row.y < 160 || row.y + row.height > 610)
            { valid = false; log += "GEOMETRY y=" + row.y + " height=" + row.height + "\n"; }
         }
         ok(valid, "settings rows fit below both tab rows and above panel bottom");
      }
      private function find(o:*, name:String):*
      {
         if(o == null) return null; if(o.name == name) return o;
         if("numChildren" in o) for(var i:int = 0; i < o.numChildren; i++)
         { var result:* = find(o.getChildAt(i), name); if(result != null) return result; }
         return null;
      }
      private function countName(o:*, name:String):int
      {
         if(o == null) return 0; var n:int = o.name == name ? 1 : 0;
         if("numChildren" in o) for(var i:int = 0; i < o.numChildren; i++) n += countName(o.getChildAt(i), name);
         return n;
      }
      private function collect(o:*, a:Array):void
      {
         if(o == null || !o.visible) return; if("settingsItem" in o) a.push(o);
         if("numChildren" in o) for(var i:int = 0; i < o.numChildren; i++) collect(o.getChildAt(i), a);
      }
      private function rows():Array { var a:Array = []; collect(main, a); return a; }
      private function fileText(file:*):String
      {
         if(!file.exists) return "";
         var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class; var s:* = new S();
         s.open(file, "read"); var value:String = s.readUTFBytes(s.bytesAvailable); s.close(); return value;
      }
      private function readApp(path:String):String { return fileText(getDefinitionByName("flash.filesystem.File")["applicationDirectory"].resolvePath(path)); }
      private function write(name:String, text:String):void
      {
         var F:Class = getDefinitionByName("flash.filesystem.File") as Class; var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var s:* = new S(); s.open(F["applicationStorageDirectory"].resolvePath(name), "write"); s.writeUTFBytes(text); s.close();
      }
      private function screenshot(name:String):void
      {
         for each(var row:* in rows()) if(row.settingsSc != null && "drawNow" in row.settingsSc) row.settingsSc.drawNow();
         var stage:* = main.stage; var bitmap:BitmapData = new BitmapData(stage.stageWidth, stage.stageHeight, false, 0); bitmap.draw(stage);
         var E:Class = getDefinitionByName("flash.display.PNGEncoderOptions") as Class;
         var bytes:* = Object(bitmap)["encode"](bitmap.rect, new E());
         var F:Class = getDefinitionByName("flash.filesystem.File") as Class; var S:Class = getDefinitionByName("flash.filesystem.FileStream") as Class;
         var s:* = new S(); s.open(F["applicationStorageDirectory"].resolvePath(name), "write"); s.writeBytes(bytes); s.close(); bitmap.dispose();
      }
      private function finish():void
      {
         var text:String = fileText(getDefinitionByName("flash.filesystem.File")["applicationStorageDirectory"].resolvePath("ModSettings.log"));
         ok(text.indexOf("lastErr=") < 0 && text.indexOf("menuStorageError=") < 0, "no UI or menu persistence error");
         if(run == "smoke")
         {
            ok(text.indexOf("groupVersion" in api ? "v0.4.0 loaded" : "v0.3.1 loaded") >= 0, "loaded settings version matches selected host");
            var frames:int = 0; var re:RegExp = /frames=(\d+)/g; var match:Object;
            while((match = re.exec(text)) != null) frames = Math.max(frames, int(match[1]));
            ok(frames >= 600, "installed host frame heartbeat continues after menu operations");
         }
         api.closeAll(); write(run + "-results.txt", log + "PASS " + checks + " assertions\n"); shutdown(0);
      }
      private function shutdown(code:int):void { timer.stop(); getDefinitionByName("flash.desktop.NativeApplication")["nativeApplication"].exit(code); }
   }
}
