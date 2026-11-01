const { chromium } = require('playwright');
const fs = require('fs');
const NAVY="#172239", BEAK="#FFB020", CHEEK="#FF9CA6", MOUTH="#4A1526", TONGUE="#FF7D8C";
const BODY="M50 96 A50 50 0 0 1 150 96 V170 Q150 188 132 188 H68 Q50 188 50 170 Z";
const WING="M57 103 C42 115 36 140 40 161 C49 156 56 142 60 127 Z";
const WING_R=WING.replace(/(-?\d+(\.\d+)?) (-?\d+(\.\d+)?)/g,(_,x,__,y)=>`${200-x} ${y}`);
const lx=82,rx=118,y=90,by=104;
function eyes(kind,W,P){return {
 friendly:`<circle cx="${lx}" cy="${y}" r="11" fill="${W}"/><circle cx="${rx}" cy="${y}" r="11" fill="${W}"/><circle cx="${lx+1.5}" cy="${y+1}" r="6.2" fill="${P}"/><circle cx="${rx-1.5}" cy="${y+1}" r="6.2" fill="${P}"/><circle cx="${lx+4}" cy="${y-2.5}" r="2.3" fill="${W}"/><circle cx="${rx+1}" cy="${y-2.5}" r="2.3" fill="${W}"/>`,
 happy:`<path d="M${lx-9} ${y+3} q9 -11 18 0 M${rx-9} ${y+3} q9 -11 18 0" stroke="${W}" stroke-width="5.5" fill="none" stroke-linecap="round"/>`,
 sleep:`<path d="M${lx-9} ${y} q9 8 18 0 M${rx-9} ${y} q9 8 18 0" stroke="${P}" stroke-width="5.5" fill="none" stroke-linecap="round"/>`,
}[kind]}
const squawkBeak=`<path d="M89 ${by+2} Q100 ${by+4} 111 ${by+2} Q108 ${by+15} 100.8 ${by+22} Q100 ${by+23} 99.2 ${by+22} Q92 ${by+15} 89 ${by+2}Z" fill="${MOUTH}"/><ellipse cx="100" cy="${by+15.5}" rx="5" ry="3" fill="${TONGUE}"/><path d="M88 ${by+3} Q93 ${by+17} 99 ${by+27} Q100 ${by+28.5} 101 ${by+27} Q107 ${by+17} 112 ${by+3} Q107 ${by+14} 100 ${by+21.5} Q93 ${by+14} 88 ${by+3}Z" fill="${BEAK}"/><path d="M88 ${by} Q100 ${by-2} 112 ${by} L101.6 ${by+10.5} Q100 ${by+12.5} 98.4 ${by+10.5}Z" fill="${BEAK}"/>`;
const closedBeak=`<path d="M91.5 ${by} Q100 ${by-1.5} 108.5 ${by} L101.6 ${by+14.5} Q100 ${by+17} 98.4 ${by+14.5} Z" fill="${BEAK}"/>`;
function penguin({eye="friendly",squawk=true,up=30,body=NAVY,belly="#fff",eyeW="#fff",eyeP=NAVY}={}){
  return `<path d="${WING}" fill="${body}" transform="rotate(${up} 56 106)"/>
  <path d="${WING_R}" fill="${body}" transform="rotate(${-up} 144 106)"/>
  <path d="${BODY}" fill="${body}"/>
  <path d="M70 188 V140 A30 30 0 0 1 130 140 V188 Z" fill="${belly}"/>
  <path d="M90 188 V176 A10 10 0 0 1 110 176 V188 Z" fill="${body}"/>
  ${eyes(eye,eyeW,eyeP)}<circle cx="64" cy="108" r="7.5" fill="${CHEEK}" opacity=".9"/><circle cx="136" cy="108" r="7.5" fill="${CHEEK}" opacity=".9"/>${squawk?squawkBeak:closedBeak}
  <ellipse cx="80" cy="189" rx="13" ry="5" fill="${BEAK}"/><ellipse cx="120" cy="189" rx="13" ry="5" fill="${BEAK}"/>`;
}
const place=inner=>`<g transform="translate(512 580) scale(4.9) translate(-100 -118)">${inner}</g>`;
const ground=c=>`<path d="M0 900 Q260 850 512 868 T1024 880 V1024 H0Z" fill="${c}"/>`;
const grad=(a,b)=>`<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs><rect width="1024" height="1024" fill="url(#g)"/>`;
const halo=(o1,o2)=>`<circle cx="512" cy="420" r="330" fill="#fff" opacity="${o1}"/><circle cx="512" cy="420" r="250" fill="#fff" opacity="${o2}"/>`;
const clouds=c=>`<g fill="${c}"><ellipse cx="170" cy="250" rx="70" ry="30"/><ellipse cx="215" cy="230" rx="50" ry="38"/><ellipse cx="870" cy="180" rx="56" ry="24"/><ellipse cx="840" cy="166" rx="38" ry="28"/></g>`;
const icons={
 AppIcon: grad('#7CC8FF','#3B82F6')+halo(.12,.14)+ground('#EAF4FF')+place(penguin())+clouds('#fff'),
 'AppIcon-Night': grad('#2E3B72','#121933')+halo(.04,.05)+
   `<path d="M250 150 A80 80 0 1 0 330 250 A62 62 0 1 1 250 150Z" fill="#FFD27A"/><g fill="#FFE6A8"><circle cx="760" cy="150" r="10"/><circle cx="880" cy="270" r="7"/><circle cx="140" cy="420" r="6"/><circle cx="640" cy="90" r="6"/><circle cx="900" cy="470" r="8"/></g><g fill="#FFE6A8" font-family="Arial Rounded MT Bold,Arial,sans-serif" font-weight="900"><text x="730" y="400" font-size="110">z</text><text x="815" y="320" font-size="76">z</text></g>`+
   ground('#2A3566')+place(penguin({eye:"sleep",squawk:false,up:0,body:"#fff",belly:NAVY})),
 'AppIcon-Mint': grad('#7FE3C2','#22A983')+halo(.12,.14)+ground('#EAFBF4')+place(penguin({eye:"happy",squawk:false,up:0}))+clouds('#fff'),
 'AppIcon-Ice': grad('#F4F8FF','#C3D5FF')+`<circle cx="512" cy="420" r="330" fill="#fff" opacity=".5"/>`+ground('#FFFFFF')+place(penguin())+`<g fill="#FF8A4C"><path d="M170 220 l12 -32 l12 32 l32 12 l-32 12 l-12 32 l-12 -32 l-32 -12z"/><path d="M850 200 l8 -22 l8 22 l22 8 l-22 8 l-8 22 l-8 -22 l-22 -8z"/></g>`,
};
(async()=>{
  const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1024,height:1024}});
  for(const [k,v] of Object.entries(icons)){
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">${v}</svg>`;
    fs.writeFileSync(`out/${k}.svg`,svg);
    await p.setContent(`<html><body style="margin:0">${svg}</body></html>`);
    await p.screenshot({path:`out/${k}.png`,clip:{x:0,y:0,width:1024,height:1024}});
  }
  const img=k=>`data:image/png;base64,${fs.readFileSync('out/'+k+'.png').toString('base64')}`;
  const cell=(k)=>`<div style="text-align:center"><img src="${img(k)}" style="width:260px;border-radius:58px;display:block"/><div style="display:flex;gap:16px;justify-content:center;margin:16px 0;align-items:end"><img src="${img(k)}" style="width:120px;border-radius:27px"/><img src="${img(k)}" style="width:60px;border-radius:13.5px"/></div><b>${k.replace('AppIcon-','').replace('AppIcon','Standard')}</b></div>`;
  await p.setViewportSize({width:1280,height:560});
  await p.setContent(`<html><body style="margin:0;padding:40px;background:#F4F6FB;font:600 26px system-ui,sans-serif;color:#1E2945;display:flex;gap:40px">${Object.keys(icons).map(cell).join('')}</body></html>`);
  await p.screenshot({path:'out/all.png',fullPage:true});
  await b.close();
})();
