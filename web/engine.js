export const ITEMS={sword:{name:'Iron Sword',damage:22,rarity:'common',text:'A reliable blade carried by the wardens.'},fang:{name:'Goblin Fang',damage:29,rarity:'uncommon',text:'A light, curved blade.'},rune:{name:'Runeblade',damage:36,rarity:'rare',text:'Imbued with the magic of ancient smiths.'},legendary:{name:'Warden Legacy',damage:48,rarity:'legendary',text:'Campaign reward. An ordinary game item.'},armor:{name:'Warden Armor',damage:0,rarity:'epic',text:'Reduces incoming damage by 30%.'}};
const spawns=[['skeleton',1260,660],['goblin',1430,780],['skeleton',1480,480],['mage',1520,1040],['goblin',1290,1070],['mage',1620,730],['skeleton',1600,1200],['boss',2070,740]];
export const props=[['elder',650,660],['shrine',330,740],['house',400,440],['house',740,490],['house',430,1080],['chest',780,850],['chest',1530,340],['chest',1510,1180],['pillar',1272,504],['pillar',1512,504],['pillar',1272,936],['pillar',1512,936],['pillar',1944,504],['pillar',2184,504],['pillar',1944,1032],['pillar',2184,1032]];
export function floor(x,y){return (x>=2&&x<=18&&y>=4&&y<=25)||(x>=18&&x<=23&&y>=13&&y<=16)||(x>=23&&x<=34&&y>=5&&y<=25)||(x>=34&&x<=38&&y>=13&&y<=16)||(x>=38&&x<=47&&y>=7&&y<=24);}
export function blocked(x,y){const tx=Math.floor(x/48),ty=Math.floor(y/48);return !floor(tx,ty)||[[26,10],[31,10],[26,19],[31,19],[40,10],[45,10],[40,21],[45,21]].some(p=>p[0]===tx&&p[1]===ty)||props.some(p=>p[0]==='house'&&Math.abs(x-p[1])<80&&y>p[2]-68&&y<p[2]-10);}
const dist=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y);
export class Game {
 constructor(){this.state='menu';this.overlay='';this.keys=new Set();this.mouse={x:750,y:360};this.camera={x:0,y:0};this.time=0;this.volume=.3;this.managedDamage=()=>0;this.notify=()=>{};this.sound=()=>{};this.open=()=>{};this.reset();}
 reset(){this.hero={x:480,y:720};this.health=100;this.stamina=100;this.gold=0;this.potions=3;this.inventory=['sword'];this.weapon='sword';this.armor=false;this.quest=0;this.killed=[];this.opened=[];this.enemies=spawns.map(([type,x,y],id)=>({id,type,x,y,hp:type==='boss'?640:type==='skeleton'?66:type==='mage'?58:46,maxhp:type==='boss'?640:type==='skeleton'?66:type==='mage'?58:46,state:'idle',timer:0,hit:0,attack:0}));this.drops=[];this.projectiles=[];this.particles=[];this.angle=0;this.swing=0;this.cooldown=0;this.invulnerable=0;this.roll=0;this.deathTimer=0;}
 start(saved=null){this.reset();if(saved&&saved.version===1){this.hero=saved.hero||this.hero;this.health=Math.max(1,Math.min(100,saved.health||100));this.gold=saved.gold||0;this.potions=saved.potions??3;this.inventory=(saved.inventory||['sword']).filter(k=>ITEMS[k]);this.weapon=this.inventory.includes(saved.weapon)?saved.weapon:'sword';this.armor=!!saved.armor&&this.inventory.includes('armor');this.quest=saved.quest||0;this.killed=saved.killed||[];this.opened=saved.opened||[];this.enemies=this.enemies.filter(e=>!this.killed.includes(e.id));if(blocked(this.hero.x,this.hero.y))this.hero={x:480,y:720};}this.state='playing';this.overlay='';this.camera={x:this.hero.x-640,y:this.hero.y-360};}
 snapshot(){return {version:1,hero:this.hero,health:this.health,gold:this.gold,potions:this.potions,inventory:this.inventory,weapon:this.weapon,armor:this.armor,quest:this.quest,killed:this.killed,opened:this.opened};}
 get damage(){return this.managedDamage()||ITEMS[this.weapon].damage;}
 move(entity,dx,dy){if(![-11,11].some(r=>blocked(entity.x+dx+r,entity.y-9)||blocked(entity.x+dx+r,entity.y+9)))entity.x+=dx;if(![-11,11].some(r=>blocked(entity.x-11,entity.y+dy+r)||blocked(entity.x+11,entity.y+dy+r)))entity.y+=dy;}
 attack(){if(this.state!=='playing'||this.overlay||this.cooldown>0||this.stamina<12)return;this.stamina-=12;this.cooldown=.34;this.swing=.22;this.sound('slash');for(const e of this.enemies){const a=Math.atan2(e.y-this.hero.y,e.x-this.hero.x),delta=Math.atan2(Math.sin(a-this.angle),Math.cos(a-this.angle));if(dist(e,this.hero)<100&&Math.abs(delta)<1.35){e.hp-=this.damage;e.hit=.18;this.burst(e.x,e.y,'#efd496',10);this.sound('hit');if(e.hp<=0)this.kill(e);}}this.enemies=this.enemies.filter(e=>e.hp>0);}
 dodge(){if(this.state!=='playing'||this.overlay||this.roll>0||this.stamina<30)return;this.stamina-=30;this.roll=.25;this.invulnerable=.35;this.rollAngle=this.angle;this.sound('roll');}
 hurt(amount){if(this.invulnerable>0||this.state!=='playing')return;this.health=Math.max(0,this.health-Math.round(amount*(this.armor?.7:1)));this.invulnerable=.55;this.sound('hurt');this.burst(this.hero.x,this.hero.y,'#bc445e',15);if(!this.health){this.state='dead';this.deathTimer=2;this.notify('You have fallen. The shrine brings you back to life.');}}
 kill(e){this.killed.push(e.id);this.drops.push({x:e.x,y:e.y,type:'gold',amount:e.type==='boss'?100:12});if(e.type==='boss'){this.inventory.push('legendary');this.quest=3;this.sound('bell');this.notify('Guardian defeated! Warden Legacy added to your inventory.');}else if(e.type==='goblin'&&!this.inventory.includes('fang'))this.drops.push({x:e.x+18,y:e.y,type:'fang'});else if(e.type==='mage'&&!this.inventory.includes('rune'))this.drops.push({x:e.x+18,y:e.y,type:'rune'});}
 burst(x,y,color,count){for(let i=0;i<count;i++){const a=Math.random()*Math.PI*2,s=40+Math.random()*130;this.particles.push({x,y,vx:Math.cos(a)*s,vy:Math.sin(a)*s,life:.5,color});}}
 interact(){if(this.state!=='playing'||this.overlay)return;const h=this.hero;
  if(dist(h,{x:650,y:820})<95){this.open('trial');return;}
  if(dist(h,{x:650,y:660})<95){if(this.quest===0){this.quest=1;this.notify('Keeper: defeat the Shadow Guardian in the eastern crypt. The portal to the south leads to a separate RGB trial.');}else if(this.quest===3){this.quest=4;this.gold+=150;this.notify('Village saved. Reward: 150 gold.');}else this.notify('Keeper: the crypt lies to the east. Earn your RGB sword at the blue portal.');return;}
  if(dist(h,{x:330,y:740})<95){this.health=100;this.stamina=100;this.notify('The shrine restored your health.');this.sound('bell');return;}
  props.filter(p=>p[0]==='chest').forEach((p,i)=>{if(dist(h,{x:p[1],y:p[2]})<80&&!this.opened.includes(i)){this.opened.push(i);this.gold+=35;this.potions++;if(i===1&&!this.inventory.includes('armor'))this.inventory.push('armor');this.notify('Chest: 35 gold and a potion'+(i===1?' · Warden Armor':''));this.sound('loot');}});
 }
 potion(){if(this.state==='playing'&&this.potions&&this.health<100){this.potions--;this.health=Math.min(100,this.health+55);this.sound('loot');}}
 update(dt){dt=Math.min(.04,dt);this.time+=dt;if(this.state==='dead'){this.deathTimer-=dt;if(this.deathTimer<=0){this.hero={x:330,y:790};this.health=100;this.stamina=100;this.state='playing';this.gold=Math.floor(this.gold*.9);}return;}if(this.state!=='playing'||this.overlay)return;
  this.cooldown=Math.max(0,this.cooldown-dt);this.swing=Math.max(0,this.swing-dt);this.invulnerable=Math.max(0,this.invulnerable-dt);this.stamina=Math.min(100,this.stamina+20*dt);
  let dx=Number(this.keys.has('KeyD'))-Number(this.keys.has('KeyA')),dy=Number(this.keys.has('KeyS'))-Number(this.keys.has('KeyW'));const length=Math.hypot(dx,dy)||1;
  this.angle=Math.atan2(this.mouse.y+this.camera.y-this.hero.y,this.mouse.x+this.camera.x-this.hero.x);
  if(this.roll>0){this.roll-=dt;dx=Math.cos(this.rollAngle);dy=Math.sin(this.rollAngle);this.move(this.hero,dx*520*dt,dy*520*dt);}else this.move(this.hero,dx/length*190*dt,dy/length*190*dt);
  this.moving=!!(dx||dy);this.camera.x+=(this.hero.x-640-this.camera.x)*Math.min(1,dt*9);this.camera.y+=(this.hero.y-360-this.camera.y)*Math.min(1,dt*9);
  if(this.quest===1&&this.hero.x>1150)this.quest=2;
  for(const e of this.enemies){e.hit=Math.max(0,e.hit-dt);e.timer-=dt;const d=dist(e,this.hero),a=Math.atan2(this.hero.y-e.y,this.hero.x-e.x);e.angle=a;
   if(e.state==='windup'){if(e.timer<=0){this.enemyAttack(e);e.state='recover';e.timer=e.type==='boss'?1.0:.7;}continue;}
   if(e.state==='recover'){if(e.timer<=0)e.state='chase';continue;}
   if(d>(e.type==='boss'?460:370)){e.state='idle';continue;}e.state='chase';
   const range=e.type==='mage'?260:e.type==='boss'?210:52;
   if(d<range&&e.timer<=0){e.state='windup';e.attack=(e.attack+1)%3;e.timer=e.type==='boss'?(e.hp<320?.65:.95):.5;continue;}
   const direction=e.type==='mage'&&d<170?-1:1,speed=e.type==='goblin'?122:e.type==='mage'?64:e.type==='boss'?85:78;
   this.move(e,Math.cos(a)*speed*dt*direction,Math.sin(a)*speed*dt*direction);
  }
  for(const p of this.projectiles){p.x+=p.vx*dt;p.y+=p.vy*dt;p.life-=dt;if(blocked(p.x,p.y))p.life=0;if(dist(p,this.hero)<20){this.hurt(p.damage);p.life=0;}}
  this.projectiles=this.projectiles.filter(p=>p.life>0);
  this.drops=this.drops.filter(p=>{if(dist(p,this.hero)>44)return true;if(p.type==='gold')this.gold+=p.amount;else if(!this.inventory.includes(p.type))this.inventory.push(p.type);this.sound('loot');return false;});
  for(const p of this.particles){p.x+=p.vx*dt;p.y+=p.vy*dt;p.life-=dt;}this.particles=this.particles.filter(p=>p.life>0);
 }
 enemyAttack(e){const d=dist(e,this.hero);if(e.type==='mage'||(e.type==='boss'&&e.attack===2)){const count=e.type==='boss'?(e.hp<320?7:5):1;for(let i=0;i<count;i++){const a=e.angle+(i-(count-1)/2)*.22;this.projectiles.push({x:e.x,y:e.y-18,vx:Math.cos(a)*230,vy:Math.sin(a)*230,damage:18,life:3});}}else if(d<(e.type==='boss'?(e.attack===0?115:190):70)){this.hurt(e.type==='boss'?28:e.type==='goblin'?10:16);}this.burst(e.x,e.y,e.type==='boss'?'#ac64ef':'#dfa064',12);}
}
