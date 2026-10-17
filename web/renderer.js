import {floor,props} from './engine.js';
export class Renderer {
 constructor(canvas,game){this.canvas=canvas;this.ctx=canvas.getContext('2d',{alpha:false});this.game=game;this.images={};}
 async load(){await Promise.all('player skeleton goblin mage boss elder floor wall earth path water tree bush house shrine chest pillar torch grave bones rubble carpet fire sword fang rune legendary armor potion gold'.split(' ').map(async name=>{const img=new Image();img.src=`/assets/${name}.png`;await img.decode();this.images[name]=img;}));this.makeMap();}
 sprite(name,x,y,scale=1,frame=0,flip=false){const c=this.ctx,img=this.images[name];if(!img)return;const animated=['player','skeleton','goblin','mage','boss','elder'].includes(name),w=animated?img.width/4:img.width,h=img.height;c.save();c.translate(Math.round(x),Math.round(y));if(flip)c.scale(-1,1);c.drawImage(img,animated?frame%4*w:0,0,w,h,-w*scale/2,-h*scale,w*scale,h*scale);c.restore();}
 makeMap(){this.map=document.createElement('canvas');this.map.width=2400;this.map.height=1440;const c=this.map.getContext('2d');c.imageSmoothingEnabled=false;for(let y=0;y<30;y++)for(let x=0;x<50;x++){let tile=floor(x,y)?(x<19?'earth':'floor'):'wall';if(x<19&&floor(x,y)&&((y===14||y===15)||(x===13&&y>11&&y<21)))tile='path';c.drawImage(this.images[tile],x*48,y*48,48,48);if(!floor(x,y)&&x<19){c.fillStyle='#09182088';c.fillRect(x*48,y*48,48,48);}}}
 draw(){const c=this.ctx,g=this.game;c.imageSmoothingEnabled=false;c.fillStyle='#070e14';c.fillRect(0,0,1280,720);c.save();c.translate(-Math.round(g.camera.x),-Math.round(g.camera.y));c.drawImage(this.map,0,0);
  for(let i=0;i<40;i++){const x=80+(i*179)%800,y=200+(i*293)%1080;if(!floor(Math.floor(x/48),Math.floor(y/48)))this.sprite('tree',x,y,2);else if(i%3===0)this.sprite('bush',x,y,1.5);}
  for(let i=0;i<18;i++)this.sprite(i%3===0?'grave':'bones',1180+(i*137)%1050,320+(i*211)%850,1.3);
  const chestProps=props.filter(p=>p[0]==='chest');const objects=props.map(p=>({type:p[0],x:p[1],y:p[2],scale:p[0]==='house'?2.6:p[0]==='elder'?1.7:1.8}));
  objects.push(...g.enemies.map(e=>({...e,scale:e.type==='boss'?2.8:1.7})),{type:'player',...g.hero,scale:1.7});objects.sort((a,b)=>a.y-b.y);
  for(const o of objects){if(o.type==='chest'&&g.opened.includes(chestProps.findIndex(p=>p[1]===o.x&&p[2]===o.y)))c.globalAlpha=.4;else if(o.type==='player'&&g.invulnerable>0)c.globalAlpha=.55+.35*Math.sin(g.time*40);
   c.fillStyle='#0006';c.beginPath();c.ellipse(o.x,o.y-3,o.type==='boss'?42:24,9,0,0,7);c.fill();if(o.hit)c.filter='brightness(2)';this.sprite(o.type,o.x,o.y,o.scale,Math.floor(g.time*7),o.type==='player'?Math.cos(g.angle)<0:Math.cos(o.angle||0)<0);c.filter='none';c.globalAlpha=1;
   if(o.hp){if(o.state==='windup'){c.strokeStyle='#eb657c';c.fillStyle='#c0445830';c.lineWidth=3;c.beginPath();c.arc(o.x,o.y,o.type==='boss'?(o.attack===1?190:110):50,0,7);c.fill();c.stroke();}if(o.hp<o.maxhp){c.fillStyle='#1c1820';c.fillRect(o.x-25,o.y-90,50,5);c.fillStyle='#cf586e';c.fillRect(o.x-25,o.y-90,50*o.hp/o.maxhp,5);}}
  }
  // Rune portal and its orbiting embers.
  c.save();c.translate(650,820);c.scale(1,.55);c.strokeStyle='#75dce8';c.lineWidth=3;c.shadowBlur=22;c.shadowColor='#60e0f0';c.beginPath();c.arc(0,0,39+Math.sin(g.time*2)*3,0,7);c.stroke();for(let i=0;i<8;i++){const a=g.time+i*Math.PI/4;c.fillStyle='#abebed';c.fillRect(Math.cos(a)*43-2,Math.sin(a)*43-2,4,4);}c.restore();
  for(const p of g.drops)this.sprite(p.type,p.x,p.y+Math.sin(g.time*4)*4,1.2);
  for(const p of g.projectiles){c.shadowColor='#be68f8';c.shadowBlur=18;c.fillStyle='#d59fff';c.beginPath();c.arc(p.x,p.y,7,0,7);c.fill();}c.shadowBlur=0;
  if(g.swing>0){c.strokeStyle='#f5da94';c.lineWidth=7;c.shadowBlur=18;c.shadowColor='#d5a754';c.beginPath();c.arc(g.hero.x,g.hero.y-20,65,g.angle-1.2,g.angle+1.2);c.stroke();c.shadowBlur=0;}
  for(const p of g.particles){c.globalAlpha=Math.max(0,p.life*2);c.fillStyle=p.color;c.beginPath();c.arc(p.x,p.y,3,0,7);c.fill();}c.globalAlpha=1;
  for(const [x,y] of [[240,520],[830,600],[1050,690],[1190,350],[1650,1100],[1900,520],[2230,900]]){this.sprite('torch',x,y,1.8);const glow=c.createRadialGradient(x,y-35,5,x,y-35,110+Math.sin(g.time*7+x)*5);glow.addColorStop(0,'#ed9c3533');glow.addColorStop(1,'#b3652000');c.fillStyle=glow;c.fillRect(x-120,y-160,240,240);}
  c.font='14px Georgia';c.textAlign='center';c.fillStyle='#d6c78e';c.fillText('Keeper · E',650,575);c.fillStyle='#8ddcde';c.fillText('RGB Trial · E',650,875);c.restore();
  const shade=c.createRadialGradient(640,360,180,640,360,760);shade.addColorStop(0,'#07101800');shade.addColorStop(1,'#030911c0');c.fillStyle=shade;c.fillRect(0,0,1280,720);
  const boss=g.enemies.find(e=>e.type==='boss');if(boss&&g.hero.x>1800){c.fillStyle='#0c111bdd';c.fillRect(400,640,480,48);c.fillStyle='#864663';c.fillRect(410,669,460*boss.hp/boss.maxhp,9);c.fillStyle='#dec8df';c.font='17px Georgia';c.textAlign='center';c.fillText(`Shadow Guardian${boss.hp<320?' · ENRAGED':''}`,640,660);}
  if(g.state==='dead'){c.fillStyle='#100b18aa';c.fillRect(0,0,1280,720);c.fillStyle='#e4a9ad';c.textAlign='center';c.font='46px Georgia';c.fillText('The Ashes Remember You',640,360);}
 }
}
