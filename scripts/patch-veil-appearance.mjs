import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const rendererPath = join(
  process.env.VEIL_CLIENT_ROOT || join(process.cwd(), "release", "Veil Terminal.app", "Contents", "Resources",
    "app", "dist", "client"),
  "assets", "index-C7zerVBL.js",
);
let source = await readFile(rendererPath, "utf8");
// The recovered bundle lost the local enum declaration in DECRQM. Class
// methods are strict: Vim's mode query otherwise throws and stalls writes.
source = source.replace("requestMode(t,s){(k=>", "requestMode(t,s){let n;(k=>");
const start = source.indexOf("function Bg(t){");
const end = source.indexOf("function Wb(t,s){t.write(s)}", start);
if (start === -1 || end === -1) throw new Error("Could not locate Veil's terminal appearance factory");

const factory = `function Bg(t){
  const boldWeight=t["use-bold-font"]===false?t["font-weight"]:(t["font-bold-weight"]??700);
  return{
    allowTransparency:true,
    cursorBlink:t["cursor-blink"]??true,
    cursorStyle:t["cursor-style"]||"block",
    fontFamily:t["font-family"],fontSize:Number(t["font-size"]),
    fontWeight:String(t["font-weight"]),fontWeightBold:String(boldWeight),
    drawBoldTextInBrightColors:t["bright-bold"]===true,
    lineHeight:Number(t["line-height"]),scrollback:10000,
    theme:{
      foreground:t.foreground,background:"#00000000",
      cursor:t["cursor-color"]||t.accent,cursorAccent:t.background,
      selectionBackground:t.selection,
      black:t.black,red:t.red,green:t.green,yellow:t.yellow,
      blue:t.blue,magenta:t.magenta,cyan:t.cyan,white:t.white,
      brightBlack:t["bright-black"]||"#68706c",
      brightRed:t["bright-red"]||t.red,brightGreen:t["bright-green"]||t.green,
      brightYellow:t["bright-yellow"]||t.yellow,brightBlue:t["bright-blue"]||t.blue,
      brightMagenta:t["bright-magenta"]||t.magenta,brightCyan:t["bright-cyan"]||t.cyan,
      brightWhite:t["bright-white"]||"#ffffff"
    }
  }
}`;

source = source.slice(0, start) + factory + source.slice(end);
const styleAnchor = '"--terminal-pad-y":`${s["padding-y"]}px`}';
const boldVariable = ',"--veil-bold-foreground":s["bold-foreground"]||s.foreground}';
if (source.split(styleAnchor).length !== 2) throw new Error("Could not locate Veil's appearance style binding");
source = source.replace(styleAnchor, styleAnchor.slice(0, -1) + boldVariable);
await writeFile(rendererPath, source);
console.log(`Patched appearance settings in ${rendererPath}`);
