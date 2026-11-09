// Original Nulora icon family. No third-party artwork or fonts.
const fs=require('fs'), path=require('path'), zlib=require('zlib');
const root=path.resolve(__dirname,'..');
function crc(b){let c=~0;for(const v of b){c^=v;for(let j=0;j<8;j++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^~0)>>>0;}
function chunk(t,b){const type=Buffer.from(t),n=Buffer.alloc(4),c=Buffer.alloc(4);n.writeUInt32BE(b.length);c.writeUInt32BE(crc(Buffer.concat([type,b])));return Buffer.concat([n,type,b,c]);}
function box(x,y,cx,cy,w,h,r){const a=Math.abs(x-cx)-w/2+r,b=Math.abs(y-cy)-h/2+r;return Math.hypot(Math.max(0,a),Math.max(0,b))+Math.min(0,Math.max(a,b))-r;}
function distance(kind,x,y){
 if(kind==='camera')return Math.min(Math.max(box(x,y,50,52,66,48,12),-box(x,y,50,52,56,38,8)),Math.abs(Math.hypot(x-50,y-52)-13)-2.4,box(x,y,36,26,22,9,4),box(x,y,73,39,5,5,2));
 if(kind==='motion')return Math.min(...[-16,0,16].map((o,i)=>box(x,y,51+i*4,50+o,58-i*9,6,3)));
 if(kind==='glass')return Math.min(Math.max(box(x,y,50,50,58,64,19),-box(x,y,50,50,50,56,15)),box(x,y,36,36,4,18,2),box(x,y,44,30,20,4,2),Math.abs(Math.hypot(x-64,y-66)-6)-1.5);
 return Math.min(Math.max(box(x,y,50,56,76,34,17),-box(x,y,50,56,68,26,13)),...[-24,-12,0,12,24].map(o=>box(x,y,50+o,56,7,10,2)));
}
function png(kind,n){const raw=Buffer.alloc((n*3+1)*n);for(let y=0;y<n;y++)for(let x=0;x<n;x++){
 const xx=(x+.5)/n*100, yy=(y+.5)/n*100,d=distance(kind,xx,yy),cover=Math.max(0,Math.min(1,.5-d*n/100));
 const glow=Math.exp(-((xx-28)**2+(yy-20)**2)/2600),base=[34+48*glow,20+26*glow,78+76*glow];
 const light=[213+30*(1-yy/100),194+42*(1-yy/100),255];let at=y*(n*3+1)+1+x*3;
 for(let c=0;c<3;c++)raw[at+c]=Math.round(base[c]*(1-cover)+light[c]*cover);
 }const ih=Buffer.alloc(13);ih.writeUInt32BE(n);ih.writeUInt32BE(n,4);ih[8]=8;ih[9]=2;return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ih),chunk('IDAT',zlib.deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
function save(p,b){const target=path.join(root,p);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,b);}
for(const size of [40,58,60,80,87,120,180,1024])save(`camera/HorizonCamera/Assets.xcassets/AppIcon.appiconset/Icon-${size}.png`,png('camera',size));
for(const [folder,kind] of [['HorizonMotion','motion'],['NuloraDock','dock'],['NuloraGlass','glass']])for(const [suffix,size] of [['',29],['@2x',58],['@3x',87]])save(`ios26/${folder}/prefs/Resources/Icon${suffix}.png`,png(kind,size));
for(const kind of ['camera','motion','dock','glass'])save(`icons/nulora-${kind}.png`,png(kind,256));
console.log('Nulora: camera, motion and dock icons generated');
