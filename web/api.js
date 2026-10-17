/** Managed RGB wallets live on the server. Browser credentials are scoped bearer tokens. */
export class RuneAPI extends EventTarget {
 constructor(qa=false) {
  super(); this.qa=qa; this.key=`runeforge-js-${qa?'test':'play'}-profiles-v1`;
  try { this.saved=JSON.parse(localStorage.getItem(this.key))||{}; } catch {this.saved={};}
  this.slot=this.saved.active||'A';this.profiles=this.saved.profiles||{};
  for(const slot of ['A','B']) this.profiles[slot] ||= {name:`${qa?'Test ':''}JS ${slot}`,key:Array.from(crypto.getRandomValues(new Uint8Array(32)),n=>n.toString(16).padStart(2,'0')).join('')};
  this.persist();this.data={items:[],players:[],history:[],service:{available:false}};this.busy=false;this.online=false;this.message='Connecting to local server…';this.lease=0;this.operation='';
 }
 persist(){localStorage.setItem(this.key,JSON.stringify({active:this.slot,profiles:this.profiles}));}
 changed(){this.dispatchEvent(new Event('change'));}
 get damage(){return this.online&&performance.now()<this.lease ? this.data.equipment?.damage||0:0;}
 async request(path,method='GET',body){
  const headers={'Content-Type':'application/json'};const token=this.profiles[this.slot].token;if(token)headers.Authorization=`Bearer ${token}`;
  const response=await fetch(path,{method,headers,body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(6000)});
  const data=await response.json();if(!response.ok){const error=new Error(typeof data.detail==='string'?data.detail:'The server rejected the request');error.code=response.status;throw error;}return data;
 }
 async run(work){if(this.busy)return;this.busy=true;this.changed();try{await work();this.online=true;}catch(error){this.lease=0;this.message=error.code?error.message:'Server offline. Campaign available; RGB items disabled.';if(!error.code||error.code===503){this.online=false;this.data.service={available:false,message:this.message};}if(error.code===401){delete this.profiles[this.slot].token;this.persist();this.online=false;}}finally{this.busy=false;this.changed();}}
 async sync(){
  for(const slot of ['A','B'])if(!this.profiles[slot].token){const p=this.profiles[slot];const r=await this.request('/api/players','POST',{name:p.name,registration_key:p.key,is_test:this.qa});Object.assign(p,{id:r.id,token:r.token});this.persist();}
  const started=performance.now();this.data=await this.request('/api/relics');this.lease=0;if(this.message==='Connecting to local server…'||this.message.startsWith('Server offline.'))this.message='';
  if(this.data.service.available&&this.data.equipment)this.lease=started+Math.min(4,Math.max(0,this.data.equipment.lease_until-this.data.server_time))*1000;
  const op=this.data.history.find(x=>x.id===this.operation);
  if(op)this.message=op.state==='settled'?`Transfer complete. Sword #${op.serial} received by player «${op.recipient_name}».`:op.error_code?'Transfer paused. Sword reserved pending wallet verification.':op.status;
 }
 refresh(){return this.run(()=>this.sync());}
 switchProfile(slot){if(this.busy||!['A','B'].includes(slot))return;this.lease=0;this.slot=slot;this.operation='';this.message='';this.data={items:[],players:[],history:[],service:{available:false}};this.persist();return this.refresh();}
 beginTrial(){return this.run(async()=>{this.operation='';this.data.trial=await this.request('/api/sessions','POST',{});await this.sync();});}
 action(action){return this.run(async()=>{const t=this.data.trial;if(!t||t.status!=='active')return;this.data.trial=await this.request(`/api/sessions/${t.id}/commands`,'POST',{action,turn:t.turn,idempotency_key:`${t.id}-${t.turn}`});if(this.data.trial.status==='won')this.message='Victory verified! The smith is issuing a real RGB sword.';await this.sync();});}
 equip(serial){return this.run(async()=>{this.operation='';this.message=(await this.request(`/api/relics/${serial}/equip`,'POST',{})).message;await this.sync();});}
 unequip(){this.lease=0;return this.run(async()=>{await this.request('/api/relics/equipment','DELETE');await this.sync();});}
 transfer(serial,recipient){this.lease=0;return this.run(async()=>{
  const key=`transfer-${this.profiles[this.slot].id}-${serial}`;let intent=JSON.parse(localStorage.getItem(key)||'null');
  if(intent&&intent.recipient!==recipient)throw new Error('Check the previous transfer first.');
  intent ||= {recipient,key:crypto.randomUUID()};localStorage.setItem(key,JSON.stringify(intent));
  try{const r=await this.request(`/api/relics/${serial}/transfer`,'POST',{recipient_id:recipient,confirm:true,idempotency_key:intent.key});this.operation=r.id;this.message=r.message;localStorage.removeItem(key);await this.sync();}
  catch(error){if([400,403,404,409,410,422,503].includes(error.code))localStorage.removeItem(key);throw error;}
 });}
}
