package
{
   import flash.display.Stage;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.text.TextField;
   import modlocales.loader.LoaderLocale;

   /** Captures UI input; clients retain their own bindings, persistence and actions. */
   public class SettingsKeybinds
   {
      private var registry:SettingsRegistry;
      private var stage:Stage;
      private var held:Object = {};
      private var blocked:Object = {};
      private var modifiers:Object = {ctrl:false,alt:false,shift:false};
      private var capture:Object;
      private var context:String = "";
      private var noticePage:String = "";
      private var notice:String = "";

      public function SettingsKeybinds(owner:SettingsRegistry) { registry = owner; }

      public function attach(value:Stage):void
      {
         if(stage === value) return;
         if(stage != null)
         {
            stage.removeEventListener(KeyboardEvent.KEY_DOWN, key, true);
            stage.removeEventListener(KeyboardEvent.KEY_DOWN, key, false);
            stage.removeEventListener(KeyboardEvent.KEY_UP, key, true);
            stage.removeEventListener(KeyboardEvent.KEY_UP, key, false);
            stage.removeEventListener(Event.DEACTIVATE, deactivate);
         }
         resetHeld(); cancel(); stage = value;
         if(stage == null) return;
         stage.addEventListener(KeyboardEvent.KEY_DOWN, key, true, 2147483647, true);
         stage.addEventListener(KeyboardEvent.KEY_DOWN, key, false, 2147483647, true);
         stage.addEventListener(KeyboardEvent.KEY_UP, key, true, 2147483647, true);
         stage.addEventListener(KeyboardEvent.KEY_UP, key, false, 2147483647, true);
         stage.addEventListener(Event.DEACTIVATE, deactivate, false, 2147483647, true);
      }

      public static function normalize(value:*):Object
      {
         var result:Object = null;
         try
         {
            var n:Number = Number(value.code);
            if(value != null && !(value.code is Boolean) && isFinite(n) && n == int(n) &&
               (n == 0 || n >= 8 && n <= 222 && [16,17,18,91,92,93].indexOf(int(n)) < 0))
               result = {code:int(n),ctrl:n != 0 && value.ctrl === true,
                  alt:n != 0 && value.alt === true,shift:n != 0 && value.shift === true};
         }
         catch(e:*) {}
         return result;
      }

      private function entry(pageId:String, itemKey:String):Object
      {
         for each(var page:Object in registry.getPages())
            if(page.modId == pageId) for each(var item:Object in page.items)
               if(item.key == itemKey && item.kind == "keybind") return {page:page,item:item};
         return null;
      }

      public function value(pageId:String, itemKey:String):Object
      {
         var found:Object = entry(pageId,itemKey), result:Object = null;
         try { if(found != null) result = normalize(found.item["get"]()); } catch(e:*) {}
         return result;
      }

      public static function equal(a:Object, b:Object):Boolean
      {
         return a != null && b != null && a.code == b.code && a.ctrl == b.ctrl &&
            a.alt == b.alt && a.shift == b.shift;
      }

      public function label(binding:*):String
      {
         var b:Object = normalize(binding);
         if(b == null) return LoaderLocale.text("读取失败");
         if(b.code == 0) return LoaderLocale.text("未绑定");
         var names:Object = {8:"Backspace",9:"Tab",13:"Enter",19:"Pause",20:"CapsLock",27:"Esc",
            32:"Space",33:"PageUp",34:"PageDown",35:"End",36:"Home",37:"Left",38:"Up",39:"Right",40:"Down",
            45:"Insert",46:"Delete",186:";",187:"=",188:",",189:"-",190:".",191:"/",192:"`",219:"[",220:"\\",221:"]",222:"'"};
         var name:String = names[b.code];
         if(b.code >= 65 && b.code <= 90 || b.code >= 48 && b.code <= 57) name = String.fromCharCode(b.code);
         else if(b.code >= 112 && b.code <= 123) name = "F" + (b.code-111);
         else if(b.code >= 96 && b.code <= 105) name = "Num" + (b.code-96);
         if(name == null) name = "Key " + b.code;
         return (b.ctrl ? "Ctrl+" : "") + (b.alt ? "Alt+" : "") + (b.shift ? "Shift+" : "") + name;
      }

      public function conflict(pageId:String, itemKey:String, binding:*):String
      {
         var b:Object = normalize(binding);
         if(b == null) return LoaderLocale.text("不能使用该按键");
         if(b.code == 0) return "";
         if(!b.ctrl && !b.alt && !b.shift)
         {
            if([9,27,35,36,45,46,192].indexOf(int(b.code)) >= 0)
               return LoaderLocale.text("该键由原版保留，请使用组合键或另选按键");
            try
            {
               var w:* = SettingsRuntime.world();
               var native:Object = w != null && w.ctr != null ? w.ctr.save() : null;
               for(var id:String in native)
                  if(String(native[id].a1) == String(b.code) || String(native[id].a2) == String(b.code))
                     return LoaderLocale.text("该单键已用于原版操作，请使用组合键或另选按键");
            }
            catch(nativeError:*) {}
         }
         for each(var page:Object in registry.getPages()) for each(var item:Object in page.items)
         {
            if(item.kind != "keybind" || page.modId == pageId && item.key == itemKey) continue;
            try
            {
               if(equal(b,normalize(item["get"]()))) return LoaderLocale.text("已被占用") + ": " +
                  registry.text(page,page.moduleName) + " / " + registry.text(page,item.label);
            }
            catch(getError:*) {}
         }
         return "";
      }

      public function matches(pageId:String, itemKey:String, event:KeyboardEvent):Boolean
      {
         if(capture != null || event == null || blocked[event.keyCode]) return false;
         var b:Object = value(pageId,itemKey);
         return b != null && b.code != 0 && b.code == event.keyCode &&
            b.ctrl == event.ctrlKey && b.alt == event.altKey && b.shift == event.shiftKey;
      }

      public function down(pageId:String, itemKey:String):Boolean
      {
         if(capture != null || busy()) return false;
         var b:Object = value(pageId,itemKey);
         return b != null && b.code != 0 && held[b.code] && !blocked[b.code] &&
            b.ctrl == modifiers.ctrl && b.alt == modifiers.alt && b.shift == modifiers.shift;
      }

      public function get capturing():Boolean { return capture != null; }
      public function waiting(pageId:String, itemKey:String):Boolean
      { return capture != null && capture.pageId == pageId && capture.itemKey == itemKey; }
      public function status(pageId:String):String { return noticePage == pageId ? notice : ""; }

      public function setContext(pageId:String):void
      {
         if(context == pageId) return;
         context = pageId;
         if(capture != null && capture.pageId != pageId) cancel();
         if(noticePage != pageId) { notice = ""; noticePage = ""; }
      }

      public function begin(pageId:String, itemKey:String):Boolean
      {
         if(entry(pageId,itemKey) == null) return false;
         capture = {pageId:pageId,itemKey:itemKey};
         context = pageId; noticePage = pageId;
         notice = LoaderLocale.text("请按新的组合键；Esc取消，Delete清除");
         try { var w:* = SettingsRuntime.world(); if(w != null && w.ctr != null) w.ctr.clearAll(); } catch(e:*) {}
         registry.keybindChanged(); return true;
      }

      public function clear(pageId:String, itemKey:String):Boolean
      { return apply(pageId,itemKey,{code:0,ctrl:false,alt:false,shift:false}); }

      public function cancel():void
      {
         if(capture == null) return;
         noticePage = capture.pageId; notice = LoaderLocale.text("已取消改键");
         capture = null; registry.keybindChanged();
      }

      private function apply(pageId:String, itemKey:String, b:Object):Boolean
      {
         var found:Object = entry(pageId,itemKey);
         if(found == null) { cancel(); return false; }
         noticePage = pageId;
         var error:String = conflict(pageId,itemKey,b);
         if(error != "") { notice = error; registry.keybindChanged(); return false; }
         try
         {
            found.item["set"](normalize(b));
            if(!equal(value(pageId,itemKey),b)) throw new Error("setter did not accept binding");
            capture = null;
            notice = LoaderLocale.text("已保存") + ": " + label(b);
            registry.keybindChanged(); return true;
         }
         catch(saveError:*)
         {
            notice = LoaderLocale.text("保存失败，请重试") + ": " + saveError;
            registry.keybindChanged();
         }
         return false;
      }

      private function key(e:KeyboardEvent):void
      {
         var isDown:Boolean = e.type == KeyboardEvent.KEY_DOWN;
         modifiers = {ctrl:e.ctrlKey,alt:e.altKey,shift:e.shiftKey};
         if(isDown) held[e.keyCode] = true; else delete held[e.keyCode];
         if(blocked[e.keyCode])
         {
            if(!isDown) { delete blocked[e.keyCode]; releaseNative(e); }
            consume(e); return;
         }
         if(capture == null) return;
         // A release whose press predates capture still belongs to the native
         // game/client. Let it clear their held state; only captured presses own
         // their later releases through the blocked branch above.
         if(!isDown) return;
         consume(e);
         blocked[e.keyCode] = true;
         if(e.keyCode == 27) { cancel(); return; }
         if([16,17,18,229].indexOf(int(e.keyCode)) >= 0) return;
         if(e.keyCode == 46) { clear(capture.pageId,capture.itemKey); return; }
         apply(capture.pageId,capture.itemKey,{code:e.keyCode,ctrl:e.ctrlKey,alt:e.altKey,shift:e.shiftKey});
      }

      private function consume(e:KeyboardEvent):void { e.stopImmediatePropagation(); e.preventDefault(); }
      private function releaseNative(e:KeyboardEvent):void
      {
         try
         {
            var w:* = SettingsRuntime.world();
            if(w != null && w.ctr != null && w.ctr.onKeyboardUpEvent is Function) w.ctr.onKeyboardUpEvent(e);
         }
         catch(err:*) {}
      }
      private function resetHeld():void { held = {}; blocked = {}; modifiers = {ctrl:false,alt:false,shift:false}; }
      private function deactivate(e:Event):void { resetHeld(); cancel(); }
      private function busy():Boolean
      {
         try
         {
            var w:* = SettingsRuntime.world();
            if(w == null || w.allStat != 1 || w.onConsol) return true;
            if(w.ctr != null && w.ctr.setkeyOn) return true;
            for each(var name:String in ["mm","pip","sats","stand"])
               if(w[name] != null && w[name].active) return true;
            // GUI.dial is internal on the real sealed GUI. Use public state;
            // probing its display child would throw and block every held key.
            if(w.gui != null && w.gui.guiPause) return true;
            if(w.gui != null && w.gui.dialScript != null && w.gui.dialScript.running) return true;
            var focus:* = stage != null ? stage.focus : null;
            if(focus is TextField && TextField(focus).type == "input" && focus.stage != null)
            {
               var visible:Boolean = true;
               for(var node:* = focus; node != null; node = node.parent) if(!node.visible) visible = false;
               if(visible) return true;
            }
         }
         catch(e:*) { return true; }
         return false;
      }
   }
}
