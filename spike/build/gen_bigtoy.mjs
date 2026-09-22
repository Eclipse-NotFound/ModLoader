import fs from 'fs';
const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\u00a0\u00e9\u4e00\u6587\u6e38\u620f\u0411\u0405\u0628\u3042';
const n = 1500000;
const pick = [];
for (let i = 0; i < n; i++) pick.push(chars[Math.floor(Math.random() * chars.length)]);
const padStr = pick.join('');
const body = 'package { import flash.display.Sprite; public class BigToy extends Sprite { public var marker:String="BIG-ALIVE"; public var ctorStageNotNull:Boolean=false; public var pad:String = "' + padStr + '"; public function BigToy(){ ctorStageNotNull = (stage != null); } } }\n';
fs.writeFileSync(process.argv[2], body);
console.log('src bytes', fs.statSync(process.argv[2]).size);
