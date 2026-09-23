package
{
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;

   /** Independent settings view, adapted from the existing MSW Pip renderer.
    * Receives only a generic registry and diagnostics; owns no gameplay or storage.
    */
   public class SettingsPipTab
   {
      private var registry:SettingsRegistry;
      private var diagnostics:SettingsLog;
      private var selection:SettingsSelection;
      private var selectedRevision:int = -1;
      private var modTabsPage:int = 0;
      private var featureTabsPage:int = 0;
      private var followSelection:Boolean = true;
      private var ownedOpt:*;
      private var renderedRevision:int = -1;
      private var rowOffset:int = 0;

      private var built:Boolean = false;
      private var myBut:Sprite = null;      // "模组"子按钮（自绘）
      private var myButHi:Sprite = null;    // 高亮层
      private var head:* = null;            // 右侧帮助栏标题
      private var helpTf:TextField = null;  // 右侧帮助文本
      private var tabRow:MovieClip = null;  // 模组子页签行
      private var resetBtn:MovieClip = null; // "恢复默认"按钮（当前页）
      private var rows:Array = null;        // 当前方设置行
      private var selPage:int = 0;
      private var panelOpen:Boolean = false;
      private var hiddenVis:Array = null;
      private var nativeButtonFrames:Array = null;
      private var cachedVpip:* = null;

      // 原版字体探测结果（从游戏现成行 nazv/numb/按钮标签抄，见 probeFonts）
      private var rowFont:String = null;
      private var rowFontSize:* = null;
      private var rowEmbed:Boolean = false;
      private var rowColor:* = null;
      private var numFont:String = null;
      private var numFontSize:* = null;
      private var numEmbed:Boolean = false;
      private var numColor:* = null;
      private var butFont:String = null;
      private var butFontSize:* = null;
      private var butEmbed:Boolean = false;
      private var butColor:* = null;        // 按钮标签颜色
      private var butFilters:Array = null;  // 按钮标签滤镜（辉光等）
      private var btnBd1:* = null;          // 原版按钮常态美术（光栅采样）
      private var btnBd2:* = null;          // 原版按钮高亮美术

      private static const HELP_DEFAULT:String = "鼠标悬停某行可查看说明。";

      public function SettingsPipTab(api:SettingsRegistry, log:SettingsLog, preferences:SettingsSelection = null)
      {
         registry = api;
         diagnostics = log;
         selection = preferences == null ? new SettingsSelection(log) : preferences;
      }

      public function isActive():Boolean
      {
         return panelOpen;
      }

      public function togglePage(w:*, modId:String):Boolean
      {
         if(w == null || !guardOk(w) || w["pip"] == null || w["pip"]["active"] != true) return false;
         if(panelOpen) { close(w["pip"]); return true; }
         return selectPage(w, modId);
      }

      public function selectPage(w:*, modId:String):Boolean
      {
         if(w == null || !guardOk(w) || w["pip"] == null || w["pip"]["active"] != true) return false;
         resolveSelection();
         var index:int = modId == "" ? selPage : -1;
         var pg:Array = pages();
         for(var i:int = 0; i < pg.length; i++) if(pg[i].modId == modId) { index = i; break; }
         if(index < 0) return false;
         var pip:* = w["pip"];
         if(qname(pip["currentPage"]) != "fe.inter::PipPageOpt") pip["onoff"](5);
         var ov:* = findOptVis(w);
         if(ov == null) return false;
         ensureBuilt(ov);
         if(modId != "") selection.choosePage(pg[index]);
         selPage = index; rowOffset = 0; renderedRevision = -1; followSelection = true;
         if(!panelOpen) open(ov, pip);
         else { ensureTabRow(ov); renderRows(ov); setRowsVisible(true); }
         return true;
      }

      public function toggleModule(w:*, id:String):Boolean
      {
         if(w == null || !guardOk(w) || w["pip"] == null || w["pip"]["active"] != true) return false;
         resolveSelection();
         if(panelOpen && pages()[selPage] != null && pages()[selPage].moduleId == id)
         { close(w["pip"]); return true; }
         return selectModule(w, id);
      }

      public function selectModule(w:*, id:String):Boolean
      {
         if(w == null || !guardOk(w) || w["pip"] == null || w["pip"]["active"] != true) return false;
         for each(var group:Object in registry.getModules())
         {
            if(group.id != id) continue;
            // Keep a temporarily absent preferred feature while this module is still loading.
            var pip:* = w["pip"];
            if(qname(pip["currentPage"]) != "fe.inter::PipPageOpt") pip["onoff"](5);
            var ov:* = findOptVis(w);
            if(ov == null) return false;
            selection.chooseModule(id);
            resolveSelection();
            ensureBuilt(ov);
            rowOffset = 0; renderedRevision = -1; followSelection = true;
            if(!panelOpen) open(ov, pip);
            else { ensureTabRow(ov); renderRows(ov); setRowsVisible(true); }
            return true;
         }
         return false;
      }

      private function resolveSelection():void
      {
         var page:Object = selection.resolve(registry.getModules());
         var index:int = page == null ? 0 : pages().indexOf(page);
         if(index != selPage || selectedRevision != int(registry.revision))
         {
            rowOffset = 0; renderedRevision = -1; followSelection = true;
         }
         selPage = index;
         selectedRevision = int(registry.revision);
      }

      public function dispose(w:*):void
      {
         if(panelOpen) close(w == null ? null : w["pip"]);
         var vpip:* = mainVpip();
         for(var i:int = 0; i <= 5; i++)
         {
            var b:* = vpip == null ? null : vpip.getChildByName("but" + i);
            if(b != null) b.removeEventListener(MouseEvent.CLICK, onLeaveClick);
            b = ownedOpt == null ? null : ownedOpt.getChildByName("but" + i);
            if(b != null) b.removeEventListener(MouseEvent.CLICK, onLeaveClick);
         }
         var owned:Array = [myBut, head, helpTf, tabRow];
         if(rows != null) owned = owned.concat(rows);
         for each(var child:* in owned)
            if(child != null && child.parent != null) child.parent.removeChild(child);
         if(btnBd1 != null) btnBd1.dispose();
         if(btnBd2 != null) btnBd2.dispose();
         rows = null; ownedOpt = null; cachedVpip = null;
      }

      // ---------------- 诊断 ----------------

      private function err(prefix:String, e:*):void
      {
         diagnostics.diagSet("lastErr", prefix + ":" + e);
         try
         {
            var st:String = e["getStackTrace"]();
            if(st != null) diagnostics.diagSet("tabTrace", st.substr(0, 400));
         }
         catch(e2:*)
         {
         }
      }

      private function snap():void
      {
         try
         {
            var s:String = "but=" + (myBut == null ? "null" : myBut["x"] + "," + myBut["y"] + ",v" + myBut["visible"]) +
               " rows=" + (rows == null ? "null" : rows.length) +
               " page=" + selPage + "/" + pages().length +
               " open=" + panelOpen;
            try
            {
               var pt:* = new Point(myBut["x"], myBut["y"]);
               pt = myBut["localToGlobal"](pt);
               s += " g=" + int(pt["x"]) + "," + int(pt["y"]);
            }
            catch(e1:*)
            {
            }
            try
            {
               if(rows != null && rows.length > 1)
               {
                  var sc0:* = rows[1]["settingsSc"];
                  s += " rowOf=" + (rowOf(sc0) != null);
               }
            }
            catch(e1c:*)
            {
            }
            try
            {
               var ov:* = myBut == null ? null : myBut["parent"];
               if(ov != null) s += " sr=" + ov["scrollRect"] + " mask=" + (ov["mask"] != null);
            }
            catch(e2:*)
            {
            }
            diagnostics.diagSet("tabSnap", s);
         }
         catch(e:*)
         {
         }
      }

      private function qname(o:*):String
      {
         try
         {
            return flash.utils.getQualifiedClassName(o);
         }
         catch(e:*)
         {
         }
         return "";
      }

      private function mainVpip():*
      {
         if(cachedVpip != null) return cachedVpip;
         try
         {
            var w:* = SettingsRuntime.world();
            if(w != null) cachedVpip = w["vpip"];
         }
         catch(e:*)
         {
         }
         return cachedVpip;
      }

      private function pages():Array
      {
         return registry.getPages();
      }

      // ---------------- 每帧 ----------------

      public function update(w:*):void
      {
         var pip:* = null;
         try
         {
            if(w == null) return;
            pip = w["pip"];
            if(pip == null) return;
         }
         catch(e0:*)
         {
            err("pipTab.stage0", e0);
            return;
         }
         var onOpt:Boolean = false;
         try
         {
            onOpt = qname(pip["currentPage"]) == "fe.inter::PipPageOpt";
         }
         catch(e1:*)
         {
            err("pipTab.stage1", e1);
            return;
         }
         if(!onOpt)
         {
            if(panelOpen)
            {
               try
               {
                  close(pip);
               }
               catch(e2:*)
               {
                  err("pipTab.stage2", e2);
               }
            }
            return;
         }
         var ov:* = null;
         try
         {
            ov = findOptVis(w);
            if(ov == null && !built) probeVpip(w);
         }
         catch(e3:*)
         {
            err("pipTab.stage3", e3);
            return;
         }
         if(ov == null) return;
         try
         {
            ensureBuilt(ov);
         }
         catch(e4:*)
         {
            err("pipTab.stage4", e4);
            snap();
            return;
         }
         if(!panelOpen) return;
         if(renderedRevision != int(registry.revision))
         {
            resolveSelection();
            ensureTabRow(ov);
            renderRows(ov);
            tabRow.visible = true;
         }
         try
         {
            if(pip["active"] != true)
            {
               close(pip);
               return;
            }
            enforce(ov);
         }
         catch(e5:*)
         {
            err("pipTab.stage5", e5);
            snap();
         }
      }

      // ---------------- 定位 Opt 页视觉 ----------------

      private function findOptVis(w:*):*
      {
         var vpip:* = w["vpip"];
         if(vpip == null) return null;
         var n:int = vpip["numChildren"];
         for(var i:int = 0; i < n; i++)
         {
            var c:* = vpip["getChildAt"](i);
            if(c == myBut || c == head || c == helpTf || c == tabRow || isMine(c)) continue;
            if(c["visible"] != true) continue;
            try
            {
               if(c["getChildByName"]("but1") == null) continue;
               if(c["getChildByName"]("but5") == null) continue;
            }
            catch(eb:*)
            {
               continue;
            }
            return c;
         }
         return null;
      }

      private function isMine(c:*):Boolean
      {
         if(rows != null)
         {
            for(var i:int = 0; i < rows.length; i++)
            {
               if(rows[i] === c) return true;
            }
         }
         return false;
      }

      /** 诊断：在 Opt 页却找不到页面视觉时，将 vpip 子级清单写入日志。 */
      private function probeVpip(w:*):void
      {
         try
         {
            if(diagnostics.diag["tabProbe"] != null) return;
         }
         catch(e0:*)
         {
         }
         try
         {
            var vpip:* = w["vpip"];
            if(vpip == null)
            {
               diagnostics.diagSet("tabProbe", "vpip=null");
               return;
            }
            var s:String = "n=" + vpip["numChildren"] + " vpipVis=" + vpip["visible"];
            var n:int = vpip["numChildren"];
            for(var i:int = 0; i < n; i++)
            {
               var c:* = vpip["getChildAt"](i);
               var hasSub:String = "";
               try
               {
                  if(c["getChildByName"] != null && c["getChildByName"]("but5") != null) hasSub = "*PAGE";
               }
               catch(e2:*)
               {
               }
               s += " |" + i + qname(c).replace(/^[^:]*::/, "").substr(0, 16) + "@" + Math.round(Number(c["x"])) + "," + Math.round(Number(c["y"])) + "v" + (c["visible"] ? 1 : 0) + hasSub;
            }
            diagnostics.diagSet("tabProbe", s.substr(0, 790));
         }
         catch(e:*)
         {
            diagnostics.diagSet("tabProbe", "probeErr:" + e);
         }
      }

      // ---------------- 自绘按钮与字体 ----------------

      private static const COL_BORDER:int = 0x1E8C5A;
      private static const COL_BORDER_HI:int = 0x00FF99;
      private static const COL_FILL:int = 0x03170E;
      private static const COL_FILL_HI:int = 0x0A3A24;
      private static const ROW_CAP:int = 16; // Two tab rows + controls; content 160..604.

      private function drawButtonFace(g:*, w:Number, h:Number, hi:Boolean):void
      {
         g.clear();
         g.beginFill(hi ? COL_FILL_HI : COL_FILL, 0.92);
         g.lineStyle(2, hi ? COL_BORDER_HI : COL_BORDER, 1);
         g.drawRect(0, 0, w, h);
         g.endFill();
      }

      /** 光栅采样原版按钮美术：临时清空其文字，帧1/帧2 各绘一张位图。
       *  全程同步执行，画面不会闪。采样失败时回退 drawButtonFace。 */
      private function sampleButtonArt(b5:*, bw:Number, bh:Number):void
      {
         try
         {
            var BD:Class = getDefinitionByName("flash.display.BitmapData") as Class;
            var fr:int = b5["currentFrame"];
            var orig:String = b5["text"]["text"];
            b5["text"]["text"] = "";
            b5["gotoAndStop"](1);
            btnBd1 = new BD(bw, bh, true, 0);
            btnBd1["draw"](b5);
            b5["gotoAndStop"](2);
            btnBd2 = new BD(bw, bh, true, 0);
            btnBd2["draw"](b5);
            b5["text"]["text"] = orig;
            b5["gotoAndStop"](fr);
         }
         catch(e:*)
         {
            btnBd1 = null;
            btnBd2 = null;
         }
      }

      private function probeFonts(ov:*):void
      {
         try
         {
            var n:int = ov["numChildren"];
            for(var i:int = 0; i < n; i++)
            {
               var c:* = ov["getChildAt"](i);
               if(c == myBut || c == head || c == helpTf) continue;
               try
               {
                  if(c["name"] != null && c["name"].indexOf("instance") != 0) continue;
               }
               catch(en:*)
               {
                  continue;
               }
               var nz:* = null;
               try
               {
                  nz = c["getChildByName"]("nazv");
               }
               catch(e2:*)
               {
               }
               if(nz == null) continue;
               var tf:* = nz["getTextFormat"]();
               rowFont = tf["font"];
               rowFontSize = tf["size"];
               rowEmbed = nz["embedFonts"] == true;
               try
               {
                  rowColor = tf["color"];
               }
               catch(e3:*)
               {
               }
               var nb:* = c["getChildByName"]("numb");
               if(nb != null)
               {
                  var nf:* = nb["getTextFormat"]();
                  numFont = nf["font"];
                  numFontSize = nf["size"];
                  numEmbed = nb["embedFonts"] == true;
                  try
                  {
                     numColor = nf["color"];
                  }
                  catch(e4:*)
                  {
                  }
               }
               break;
            }
         }
         catch(ea:*)
         {
         }
         try
         {
            var b5:* = ov["getChildByName"]("but5");
            if(b5 != null && b5["text"] != null)
            {
               var bf:* = b5["text"]["getTextFormat"]();
               butFont = bf["font"];
               butFontSize = bf["size"];
               butEmbed = b5["text"]["embedFonts"] == true;
               try
               {
                  butColor = bf["color"];
               }
               catch(ec1:*)
               {
               }
               try
               {
                  var fls:Array = b5["text"]["filters"];
                  if(fls != null && fls.length > 0) butFilters = fls;
               }
               catch(ec2:*)
               {
               }
            }
         }
         catch(eb:*)
         {
         }
         diagnostics.diagSet("tabFont", (rowFont == null ? "?" : rowFont + "/" + rowFontSize + "/embed" + rowEmbed + "/c" + rowColor) +
            " num=" + (numFont == null ? "?" : numFont + "/" + numFontSize + "/c" + numColor) +
            " but=" + (butFont == null ? "?" : butFont + "/" + butFontSize + "/embed" + butEmbed));
      }

      /** kind: "label"=行标签 / "value"=数值 / "button"=按钮。
       *  字体规格分别抄自游戏行的 nazv / numb / 按钮标签；label/value 另挂
       *  原版样式表（PipPage.setStyle），渲染机制与原版一致。 */
      private function makeLabel(text:String, size:int, color:int, kind:String = "label"):TextField
      {
         var tf:TextField = new TextField();
         var fmt:TextFormat = new TextFormat();
         var fname:String = rowFont;
         var fsize:* = rowFontSize;
         var fcolor:* = rowColor != null ? rowColor : color;
         var fembed:Boolean = rowEmbed;
         if(kind == "value")
         {
            if(numFont != null) fname = numFont;
            if(numFontSize != null) fsize = numFontSize;
            if(numColor != null) fcolor = numColor;
            fembed = numEmbed;
         }
         else if(kind == "button")
         {
            if(butFont != null) fname = butFont;
            if(butFontSize != null) fsize = butFontSize;
            if(butColor != null) fcolor = butColor;
            fembed = butEmbed;
         }
         else if(kind == "chip")
         {
            // 页签：行字体 + 指定字号（页签是次级控件，不跟按钮的 20 号）
            if(butColor != null) fcolor = butColor;
            fembed = rowEmbed;
         }
         if(fname != null) fmt.font = fname; else fmt.font = "SimHei";
         if(fsize != null) fmt.size = fsize; else fmt.size = size;
         fmt.color = fcolor;
         tf.defaultTextFormat = fmt;
         try
         {
            tf.embedFonts = fembed;
            if(kind == "button" && butFilters != null) tf["filters"] = butFilters;
         }
         catch(ee:*)
         {
         }
         if(kind != "button")
         {
            try
            {
               var st:Class = getDefinitionByName("fe.inter::PipPage") as Class;
               if(st != null) st["setStyle"](tf);
            }
            catch(es:*)
            {
            }
         }
         tf.text = text;
         tf.selectable = false;
         tf.mouseEnabled = false;
         tf.autoSize = TextFieldAutoSize.LEFT;
         return tf;
      }

      // ---------------- 构建 ----------------

      private function ensureBuilt(ov:*):void
      {
         if(built) return;
         ownedOpt = ov;
         cachedVpip = null;
         diagnostics.diagSet("tabStage", "build");
         probeFonts(ov);
         var b5:* = ov["getChildByName"]("but5");
         var bw:Number = 120;
         var bh:Number = 34;
         if(b5 != null)
         {
            try
            {
               if(Number(b5["width"]) > 40) bw = Number(b5["width"]);
               if(Number(b5["height"]) > 14) bh = Number(b5["height"]);
            }
            catch(e0:*)
            {
            }
         }
         myBut = new Sprite();
         myBut.name = "ModSettingsButton";
         myButHi = new Sprite();
         sampleButtonArt(b5, bw, bh);
         var useArt:Boolean = btnBd1 != null && btnBd2 != null;
         if(useArt)
         {
            // 原版按钮美术直接作底图（常态/高亮两态）
            var bmpC:Class = getDefinitionByName("flash.display::Bitmap") as Class;
            myBut["addChild"](new bmpC(btnBd1));
            myButHi["addChild"](new bmpC(btnBd2));
         }
         else
         {
            drawButtonFace(myButHi["graphics"], bw, bh, true);
            drawButtonFace(myBut["graphics"], bw, bh, false);
         }
         myButHi["visible"] = false;
         var lt:TextField = makeLabel("模组", 15, 0xE8FFE8, "button");
         lt.x = (bw - lt.width) / 2;
         lt.y = (bh - lt.height) / 2;
         try
         {
            // Preserve the native fixed text box. textHeight also includes leading,
            // so using it to recalibrate the font enlarged 20px text to 22px.
            if(b5 != null && b5["text"] != null)
            {
               var nativeText:TextField = b5["text"] as TextField;
               lt.autoSize = nativeText.autoSize;
               lt.wordWrap = nativeText.wordWrap;
               lt.multiline = nativeText.multiline;
               lt.embedFonts = nativeText.embedFonts;
               lt.antiAliasType = nativeText.antiAliasType;
               lt.gridFitType = nativeText.gridFitType;
               lt.sharpness = nativeText.sharpness;
               lt.thickness = nativeText.thickness;
               lt.defaultTextFormat = nativeText.getTextFormat();
               lt.setTextFormat(nativeText.getTextFormat());
               lt.filters = nativeText.filters;
               lt.transform.colorTransform = nativeText.transform.colorTransform;
               lt.width = nativeText.width;
               lt.height = nativeText.height;
               lt.scaleX = nativeText.scaleX;
               lt.scaleY = nativeText.scaleY;
               lt.rotation = nativeText.rotation;
               lt.x = nativeText.x;
               lt.y = nativeText.y;
            }
         }
         catch(ecal:*)
         {
            err("buttonStyle", ecal);
         }
         myBut["addChild"](myButHi);
         myBut["addChild"](lt);
         myBut["mouseChildren"] = false;
         myBut["buttonMode"] = true;
         if(b5 != null)
         {
            myBut["x"] = Number(b5["x"]) + bw + 2;
            myBut["y"] = Number(b5["y"]);
         }
         else
         {
            myBut["x"] = 30;
            myBut["y"] = 40;
         }
         myBut.addEventListener(MouseEvent.CLICK, onButClick);
         ov["addChild"](myBut);
         var vpip:* = mainVpip();
         for(var j:int = 0; j <= 5; j++)
         {
            var mb:* = vpip == null ? null : vpip["getChildByName"]("but" + j);
            if(mb != null) mb.addEventListener(MouseEvent.CLICK, onLeaveClick, false, 1);
         }
         for(var k:int = 1; k <= 5; k++)
         {
            var ob:* = ov["getChildByName"]("but" + k);
            // Restore the suspended page BEFORE native navigation rebuilds its target.
            if(ob != null) ob.addEventListener(MouseEvent.CLICK, onLeaveClick, false, 1);
         }
         head = makeLabel("", 16, 0x00FF99);
         head["x"] = 600;
         head["y"] = 164;
         head["visible"] = false;
         ov["addChild"](head);
         helpTf = makeLabel(HELP_DEFAULT, 13, 0x9FE8C8);
         helpTf["x"] = 600;
         helpTf["y"] = 194;
         helpTf["width"] = 230;
         helpTf["wordWrap"] = true;
         helpTf["autoSize"] = TextFieldAutoSize.NONE;
         helpTf["height"] = 300;
         helpTf["visible"] = false;
         ov["addChild"](helpTf);
         rows = [];
         built = true;
         ensureTabRow(ov);
         diagnostics.diagSet("pages", pages().length);
         diagnostics.diagAdd("tabBuild");
         snap();
      }

      /** Bounded navigation: any page count and any item count remain reachable. */
      private function ensureTabRow(ov:*):void
      {
         var pg:Array = pages();
         if(selPage >= pg.length) selPage = 0;
         if(tabRow != null && renderedRevision == int(registry.revision)) return;
         if(tabRow != null && tabRow.parent != null) tabRow.parent.removeChild(tabRow);
         tabRow = new MovieClip();
         tabRow.name = "ModSettingsNavigation";
         tabRow.x = 30; tabRow.y = 66; tabRow.visible = panelOpen;
         var page:* = pg.length > 0 ? pg[selPage] : null;
         var count:int = page == null ? 0 : page.items.length;
         rowOffset = count == 0 ? 0 : Math.min(rowOffset, int((count - 1) / ROW_CAP) * ROW_CAP);
         var groups:Array = registry.getModules();
         var modTabs:Array = [], featureTabs:Array = [];
         for each(var group:Object in groups)
         {
            modTabs.push({id:group.id, label:group.name});
            if(page == null || page.moduleId != group.id) continue;
            if(group.pages.length == 1 && group.pages[0].featureName == "") continue;
            for each(var feature:Object in group.pages)
               featureTabs.push({id:feature.modId, label:feature.featureName == "" ? feature.displayName : feature.featureName});
         }
         tabRow["moduleId"] = page == null ? "" : page.moduleId;
         tabRow["pageId"] = page == null ? "" : page.modId;
         buildTabStrip(modTabs, page == null ? "" : page.moduleId, false);
         // Reserve the second row even for an unclassified module.
         if(featureTabs.length > 0) buildTabStrip(featureTabs, page.modId, true);
         followSelection = false;
         resetBtn = navigationButton("恢复默认", "SettingsReset", 0, 110, onResetClick, page != null, 60);
         navigationButton("设置上页", "SettingsPreviousItems", 314, 80, function(e:*):void {
            changeItems(-ROW_CAP);
         }, rowOffset > 0, 60);
         var position:TextField = makeLabel(count == 0 ? "0/0" :
            (int(rowOffset / ROW_CAP) + 1) + "/" + Math.ceil(count / ROW_CAP), 14, 0xD8FFE8, "chip");
         position.name = "SettingsItemsPosition";
         position.x = 408; position.y = 62; tabRow.addChild(position);
         navigationButton("设置下页", "SettingsNextItems", 470, 80, function(e:*):void {
            changeItems(ROW_CAP);
         }, rowOffset + ROW_CAP < count, 60);
         ov.addChild(tabRow);
      }

      private function buildTabStrip(tabs:Array, selected:String, features:Boolean):void
      {
         var y:Number = features ? 30 : 0;
         var prefix:String = features ? "SettingsFeature" : "SettingsModule";
         var caption:TextField = makeLabel(features ? "功能" : "模组", 14, 0x9FE8C8, "chip");
         caption.x = 0; caption.y = y + 2; tabRow.addChild(caption);
         var chunks:Array = [[]], used:Number = 0, selectedChunk:int = 0;
         for each(var tab:Object in tabs)
         {
            var measure:TextField = makeLabel(tab.label, 14, 0xD8FFE8, "chip");
            tab.width = Math.max(72, Math.min(180, measure.width + 20));
            if(used + tab.width > 562 && chunks[chunks.length - 1].length > 0)
            { chunks.push([]); used = 0; }
            if(tab.id == selected) selectedChunk = chunks.length - 1;
            chunks[chunks.length - 1].push(tab); used += tab.width + 6;
         }
         var current:int = features ? featureTabsPage : modTabsPage;
         current = followSelection ? selectedChunk : Math.max(0, Math.min(current, chunks.length - 1));
         if(features) featureTabsPage = current; else modTabsPage = current;
         var x:Number = 48;
         for each(tab in chunks[current])
         {
            var button:MovieClip = navigationButton(tab.label, prefix + "Tab:" + tab.id,
               x, tab.width, tabHandler(tab.id, features), true, y, tab.id == selected);
            button["settingsSelected"] = tab.id == selected;
            x += tab.width + 6;
         }
         if(chunks.length > 1)
         {
            navigationButton("◀", prefix + "Previous", 628, 30, pageTabsHandler(features, -1), current > 0, y);
            var counter:TextField = makeLabel((current + 1) + "/" + chunks.length, 14, 0xD8FFE8, "chip");
            counter.name = prefix + "Position"; counter.x = 674; counter.y = y + 2; tabRow.addChild(counter);
            navigationButton("▶", prefix + "Next", 736, 30, pageTabsHandler(features, 1), current < chunks.length - 1, y);
         }
      }

      private function tabHandler(id:String, features:Boolean):Function
      {
         return function(e:*):void {
            if(features) selectPage(SettingsRuntime.world(), id);
            else selectModule(SettingsRuntime.world(), id);
         };
      }

      private function pageTabsHandler(features:Boolean, delta:int):Function
      {
         return function(e:*):void {
            if(features) featureTabsPage += delta; else modTabsPage += delta;
            followSelection = false; renderedRevision = -1;
            ensureTabRow(ownedOpt); renderRows(ownedOpt); setRowsVisible(panelOpen);
         };
      }

      private function navigationButton(label:String, name:String, x:Number, width:Number,
                                        handler:Function, enabled:Boolean, y:Number = 0, selected:Boolean = false):MovieClip
      {
         var button:MovieClip = new MovieClip();
         button.name = name; button.x = x; button.y = y;
         drawButtonFace(button.graphics, width, 24, selected);
         var direction:int = label == "◀" ? -1 : label == "▶" ? 1 : 0;
         if(direction != 0)
         {
            // Draw arrows directly: the game's font does not contain triangle glyphs.
            button.graphics.lineStyle(); button.graphics.beginFill(0x00FF99);
            button.graphics.moveTo(width / 2 + direction * 5, 12);
            button.graphics.lineTo(width / 2 - direction * 4, 6);
            button.graphics.lineTo(width / 2 - direction * 4, 18);
            button.graphics.lineTo(width / 2 + direction * 5, 12);
            button.graphics.endFill();
         }
         else
         {
            var tf:TextField = makeLabel(label, 14, 0xD8FFE8, "chip");
            while(tf.width > width - 12 && tf.text.length > 2) tf.text = tf.text.substr(0, tf.text.length - 2) + "…";
            tf.x = (width - tf.width) / 2; tf.y = 2; button.addChild(tf);
         }
         button.mouseChildren = false; button.mouseEnabled = enabled;
         button.buttonMode = enabled; button.alpha = enabled ? 1 : 0.4;
         if(enabled) button.addEventListener(MouseEvent.CLICK, handler);
         tabRow.addChild(button);
         return button;
      }

      private function changeItems(delta:int):void
      {
         rowOffset += delta;
         if(rowOffset < 0) rowOffset = 0;
         renderedRevision = -1;
         ensureTabRow(ownedOpt);
         renderRows(ownedOpt);
         setRowsVisible(panelOpen);
      }

      private function onResetClick(e:*):void
      {
         try
         {
            var w:* = SettingsRuntime.world();
            if(w == null) return;
            var pg:Array = pages();
            if(selPage >= pg.length) return;
            var result:Object = registry.resetPage(selPage);
            var ov:* = findOptVis(w);
            if(ov != null)
            {
               renderedRevision = -1;
               ensureTabRow(ov);
               renderRows(ov);
            }
            setRowsVisible(true);
            if(helpTf != null) helpTf["text"] = "已恢复默认（" + result.applied + " 项）" + (result.failed > 0 ? "；失败 " + result.failed + " 项，请查看日志。" : "。");
            diagnostics.diagAdd("reset");
         }
         catch(failure:*)
         {
            err("pageReset", failure);
         }
      }

      // ---------------- 行渲染（按当前注册页） ----------------

      private function renderRows(ov:*):void
      {
         if(rows != null)
         {
            for(var ri:int = 0; ri < rows.length; ri++)
            {
               try
               {
                  ov["removeChild"](rows[ri]);
               }
               catch(erm:*)
               {
               }
            }
         }
         rows = [];
         renderedRevision = int(registry.revision);
         var pg:Array = pages();
         if(selPage >= pg.length) selPage = 0;
         var page:* = pg[selPage];
         if(page == null)
         {
            if(head != null) head.text = "模组设置";
            if(helpTf != null) helpTf.text = "暂无已注册的设置页。启用支持此入口的模组后会自动出现。";
            return;
         }
         var items:Array = page["items"];
         if(head != null) head["text"] = (page["displayName"] == null ? "" : page["displayName"]) + " 设置";
         if(helpTf != null) helpTf["text"] = (page["desc"] == null || page["desc"] == "") ? HELP_DEFAULT : page["desc"];
         if(items == null) return;
         var n:int = Math.min(items.length - rowOffset, ROW_CAP);
         for(var i:int = 0; i < n; i++)
         {
            var it:Object = items[rowOffset + i];
            if(it == null || it["key"] == null) continue;
            var r:MovieClip = new MovieClip();
            r["x"] = 30;
            r["y"] = 160 + i * 28;
            var bg:Sprite = new Sprite();
            bg["graphics"].beginFill(0x000000, 1);
            bg["graphics"].lineStyle(1, 0x0F4A2E, 1);
            bg["graphics"].drawRect(0, 0, 550, 24);
            bg["graphics"].endFill();
            bg["mouseEnabled"] = false;
            r["addChild"](bg);
            var lt:TextField = makeLabel(it["label"] == null ? String(it["key"]) : String(it["label"]), 14, 0xD8FFE8, "label");
            lt["x"] = 10;
            lt["y"] = 3;
            r["addChild"](lt);
            r["settingsItem"] = it;
            var kind:String = it["kind"] == null ? "check" : it["kind"];
            var cur:* = getItemVal(it);
            if(kind == "check")
            {
               var cb:* = makeCheck();
               cb["selected"] = cur == true;
               cb["x"] = 360;
               cb["y"] = 2;
               cb["addEventListener"]("change", onCheck);
               r["addChild"](cb);
               r["settingsSc"] = cb;
            }
            else
            {
               var numb:TextField = makeLabel(fmtVal(it, cur), 13, 0xE8FFE8, "value");
               numb["x"] = 505;
               numb["y"] = 4;
               r["addChild"](numb);
               r["settingsNumb"] = numb;
               var sc:* = makeSlider(it, cur);
               if(sc != null)
               {
                  sc["addEventListener"]("scroll", onScroll);
                  r["addChild"](sc);
                  r["settingsSc"] = sc;
               }
               else
               {
                  var less:MovieClip = miniBtn("◀", 256);
                  var more:MovieClip = miniBtn("▶", 445);
                  less["settingsDir"] = -1;
                  more["settingsDir"] = 1;
                  less.addEventListener(MouseEvent.CLICK, onStep);
                  more.addEventListener(MouseEvent.CLICK, onStep);
                  r["addChild"](less);
                  r["addChild"](more);
               }
            }
            r.addEventListener(MouseEvent.MOUSE_OVER, onRowHover);
            r.addEventListener(MouseEvent.MOUSE_OUT, onRowOut);
            r["visible"] = false;
            ov["addChild"](r);
            rows[rows.length] = r;
         }
      }

      private function makeCheck():*
      {
         try
         {
            var cls:Class = getDefinitionByName("fl.controls::CheckBox") as Class;
            if(cls != null) return new cls();
         }
         catch(e0:*)
         {
         }
         var box:MovieClip = new MovieClip();
         drawToggle(box, false);
         box["buttonMode"] = true;
         box.addEventListener(MouseEvent.CLICK, onHandToggle);
         return box;
      }

      private function makeSlider(it:Object, cur:*):*
      {
         try
         {
            var cls:Class = getDefinitionByName("fl.controls::ScrollBar") as Class;
            if(cls != null)
            {
               var sc:* = new cls();
               sc["direction"] = "horizontal";
               sc["width"] = 240;
               sc["height"] = 14;
               sc["x"] = 256;
               sc["y"] = 5;
               sc["minScrollPosition"] = 0;
               sc["maxScrollPosition"] = Math.round((Number(it["max"]) - Number(it["min"])) / Number(it["step"]));
               sc["scrollPosition"] = posOf(it, cur);
               return sc;
            }
         }
         catch(e:*)
         {
         }
         return null;
      }

      private function drawToggle(box:*, on:Boolean):void
      {
         box["graphics"].clear();
         box["graphics"].lineStyle(2, on ? COL_BORDER_HI : COL_BORDER, 1);
         box["graphics"].beginFill(on ? COL_FILL_HI : COL_FILL, 1);
         box["graphics"].drawRect(0, 0, 20, 20);
         box["graphics"].endFill();
         if(on)
         {
            box["graphics"].lineStyle(3, 0x00FF99, 1);
            box["graphics"].moveTo(4, 10);
            box["graphics"].lineTo(9, 15);
            box["graphics"].lineTo(16, 5);
         }
      }

      private function miniBtn(txt:String, x:Number):MovieClip
      {
         var s:MovieClip = new MovieClip();
         drawButtonFace(s["graphics"], 40, 20, false);
         var lt:TextField = makeLabel(txt, 12, 0xE8FFE8, "button");
         lt["x"] = (40 - lt["width"]) / 2;
         lt["y"] = 2;
         s["addChild"](lt);
         s["x"] = x;
         s["y"] = 4;
         s["buttonMode"] = true;
         s["mouseChildren"] = false;
         return s;
      }

      // ---------------- 值换算（通用契约：min/max/step） ----------------

      private function getItemVal(it:Object):*
      {
         try
         {
            return it["get"]();
         }
         catch(e:*)
         {
            err("itemGet:" + it["key"], e);
         }
         return null;
      }

      private function posOf(it:Object, v:*):Number
      {
         var st:Number = Number(it["step"]);
         if(st <= 0) st = 1;
         return Math.round((Number(v) - Number(it["min"])) / st);
      }

      private function valOf(it:Object, pos:Number):*
      {
         var st:Number = Number(it["step"]);
         if(st <= 0) st = 1;
         return Number(it["min"]) + Math.round(pos) * st;
      }

      private function fmtVal(it:Object, v:*):String
      {
         var st:Number = Number(it["step"]);
         var suffix:String = it["suffix"] == null ? "" : String(it["suffix"]);
         if(st >= 1) return String(Math.round(Number(v))) + suffix;
         var d:int = 0;
         var t:Number = st;
         while(t > 0 && t < 1 && d < 4)
         {
            t *= 10;
            d += 1;
         }
         return Number(v).toFixed(d) + suffix;
      }

      // ---------------- 控件事件 ----------------

      private function rowOf(o:*):*
      {
         while(o != null)
         {
            var k:* = null;
            try
            {
               // 密封类（fl.controls.*）访问缺失属性抛 #1069：跳过并继续向父级找
               k = o["settingsItem"];
            }
            catch(e:*)
            {
               k = null;
            }
            if(k != null) return o;
            o = o["parent"];
         }
         return null;
      }

      private function onCheck(e:*):void
      {
         try
         {
            var cb:* = e["currentTarget"];
            var row:* = rowOf(cb);
            if(row == null) return;
            var it:Object = row["settingsItem"];
            it["set"](cb["selected"] == true);
         }
         catch(err2:*)
         {
            err("tabCheck", err2);
         }
      }

      private function onHandToggle(e:*):void
      {
         try
         {
            var box:* = e["currentTarget"];
            var row:* = rowOf(box);
            if(row == null) return;
            var it:Object = row["settingsItem"];
            var cur:Boolean = getItemVal(it) == true;
            it["set"](!cur);
            drawToggle(box, getItemVal(it) == true);
         }
         catch(err2:*)
         {
            err("tabToggleBox", err2);
         }
      }

      private function onScroll(e:*):void
      {
         try
         {
            var sc:* = e["currentTarget"];
            var row:* = rowOf(sc);
            if(row == null) return;
            var it:Object = row["settingsItem"];
            var v:* = valOf(it, Number(sc["scrollPosition"]));
            v = Math.max(Number(it["min"]), Math.min(Number(it["max"]), v));
            it["set"](v);
            if(row["settingsNumb"] != null) row["settingsNumb"]["text"] = fmtVal(it, v);
            // 拖动期间不落盘（D-035）：关面板时宿主统一调各注册方 onPageClose
         }
         catch(err2:*)
         {
            err("tabScroll", err2);
         }
      }

      private function onStep(e:*):void
      {
         try
         {
            var btn:* = e["currentTarget"];
            var row:* = rowOf(btn);
            if(row == null) return;
            var it:Object = row["settingsItem"];
            var v:Number = Number(getItemVal(it)) + Number(btn["settingsDir"]) * Number(it["step"]);
            v = Math.max(Number(it["min"]), Math.min(Number(it["max"]), v));
            it["set"](v);
            if(row["settingsNumb"] != null) row["settingsNumb"]["text"] = fmtVal(it, getItemVal(it));
         }
         catch(err2:*)
         {
            err("tabStep", err2);
         }
      }

      private function onRowHover(e:*):void
      {
         try
         {
            var row:* = rowOf(e["currentTarget"]);
            if(row == null) return;
            var it:Object = row["settingsItem"];
            var hint:String = it["hint"] == null ? "" : it["hint"];
            if(helpTf != null) helpTf["text"] = it["label"] + (hint != "" ? "：\n" + hint : "");
         }
         catch(e:*)
         {
         }
      }

      private function onRowOut(e:*):void
      {
         try
         {
            if(helpTf != null)
            {
               var pg:Array = pages();
               var d:String = selPage < pg.length ? pg[selPage]["desc"] : null;
               helpTf["text"] = (d == null || d == "") ? HELP_DEFAULT : d;
            }
         }
         catch(e:*)
         {
         }
      }

      private function guardOk(w:*):Boolean
      {
         try
         {
            var ctr:* = w["ctr"];
            if(ctr != null && ctr["setkeyOn"] == true) return false;
         }
         catch(e:*)
         {
         }
         return true;
      }

      private function onButClick(e:*):void
      {
         try
         {
            var w:* = SettingsRuntime.world();
            if(w == null) return;
            var pip:* = w["pip"];
            if(pip == null || pip["active"] != true) return;
            if(!guardOk(w)) return;
            if(panelOpen) close(pip);
            else
            {
               var ov:* = findOptVis(w);
               if(ov != null) open(ov, pip);
            }
         }
         catch(err2:*)
         {
            err("tabClick", err2);
            snap();
         }
      }

      private function onLeaveClick(e:*):void
      {
         try
         {
            if(!panelOpen) return;
            var w:* = SettingsRuntime.world();
            if(w == null || !guardOk(w)) return;
            close(w["pip"]);
         }
         catch(err2:*)
         {
            err("tabLeave", err2);
         }
      }

      // ---------------- 打开 / 关闭 ----------------

      private function open(ov:*, pip:*):void
      {
         resolveSelection();
         followSelection = true; renderedRevision = -1;
         panelOpen = true;
         hiddenVis = [];
         suppressGameContent(ov, true);
         nativeButtonFrames = [];
         for(var i:int = 1; i <= 5; i++)
         {
            var b:* = ov["getChildByName"]("but" + i);
            if(b != null)
            {
               nativeButtonFrames.push({button:b, frame:b.currentFrame});
               b["gotoAndStop"](1);
            }
         }
         if(myBut != null) myButHi["visible"] = true;
         ensureTabRow(ov);
         if(tabRow != null) tabRow["visible"] = true;
         renderRows(ov);
         setRowsVisible(true);
         if(helpTf != null) helpTf.visible = true;
         if(head != null) head.visible = true;
         try
         {
            pip["snd"](2);
         }
         catch(e:*)
         {
         }
         diagnostics.diagAdd("tabOn");
         snap();
      }

      private function close(pip:*):void
      {
         panelOpen = false;
         if(myBut != null) myButHi["visible"] = false;
         if(nativeButtonFrames != null)
         {
            for each(var saved:Object in nativeButtonFrames) saved.button.gotoAndStop(saved.frame);
            nativeButtonFrames = null;
         }
         if(hiddenVis != null)
         {
            for(var i:int = 0; i < hiddenVis.length; i++)
            {
               try
               {
                  hiddenVis[i]["visible"] = true;
               }
               catch(e:*)
               {
               }
            }
            hiddenVis = null;
         }
         setRowsVisible(false);
         if(helpTf != null) helpTf["visible"] = false;
         if(head != null) head["visible"] = false;
         if(tabRow != null) tabRow["visible"] = false;
         registry.closeAll();
         diagnostics.diagAdd("tabOff");
      }

      private function suppressGameContent(ov:*, record:Boolean):void
      {
         var n:int = ov["numChildren"];
         for(var i:int = n - 1; i >= 0; i--)
         {
            var c:* = ov["getChildAt"](i);
            if(c == myBut || c == head || c == helpTf || c == tabRow || isMine(c)) continue;
            var nm:String = "";
            try
            {
               nm = c["name"];
            }
            catch(en:*)
            {
            }
            if(nm != null && nm.length == 4 && nm.indexOf("but") == 0) continue; // 子按钮
            try
            {
               // Large artwork is the frame; large text containers include the log
               // page (850x550) and must be suspended just like the normal rows.
               if(Number(c["width"]) > 800 && Number(c["height"]) > 400 && !containsText(c)) continue;
            }
            catch(eg:*)
            {
            }
            if(c["visible"] != true) continue;
            c["visible"] = false;
            if(record) hiddenVis[hiddenVis.length] = c;
         }
      }

      private function containsText(c:*):Boolean
      {
         if(c == null) return false;
         if(c is TextField) return true;
         if("numChildren" in c)
            for(var i:int = 0; i < c.numChildren; i++)
               if(containsText(c.getChildAt(i))) return true;
         return false;
      }

      private function enforce(ov:*):void
      {
         suppressGameContent(ov, false);
         setRowsVisible(true);
      }

      private function setRowsVisible(v:Boolean):void
      {
         if(rows != null)
         {
            for(var i:int = 0; i < rows.length; i++)
            {
               rows[i]["visible"] = v;
            }
         }
      }
   }
}
