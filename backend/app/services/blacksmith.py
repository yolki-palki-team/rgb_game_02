"""Small allowlisted model context; no wallet adapter, signing or reward calls."""
import asyncio,os
from pathlib import Path
import httpx
from sqlalchemy import select,or_
from ..models import (InventoryEntry,Item,ItemInstance,ItemOperation,RelicEquipment,GameSession,NPCMessage,NPCConversation)
from ..api.managed import usable,service_status

MODEL='QWEN3_4B_Q4_K_M'
ERRORS={
 'service_offline':'The local blacksmith service is offline. Start RuneForge, then retry.',
 'model_not_ready':'The local model is still loading. Wait for Ready, then retry.',
 'model_busy':'The smith is answering another visitor. Try again shortly.',
 'model_load_failed':'The local model could not load. Check the download or free memory, then retry.',
 'inference_timeout':'The smith took too long to reply. Your message is saved; retry when ready.',
 'inference_incomplete':'The reply was interrupted. Retry your message.',
 'invalid_response':'The model could not produce a valid short English reply. Please retry.',
 'inference_failed':'The local model could not answer. Please retry.',
 'server_restarted':'The game server restarted before the reply completed. Please retry.',
 'cancelled':'The reply was cancelled. Please retry.',
}
LOCAL_ITEMS={
 'iron':{'name':"Warden's Iron",'damage':22},'fang':{'name':'Briar Fang','damage':29},
 'rune':{'name':'Covenant Edge','damage':36},'legendary':{'name':'Dawn of the Forsaken','damage':48},
 'armor':{'name':'Ashen Plate','damage_reduction_percent':30},
}

def facts_for(db,player_id,campaign):
 # Only this authenticated player's related instances. Never accept a requested owner/asset ID.
 operations=list(db.scalars(select(ItemOperation).where(or_(ItemOperation.requester_id==player_id,ItemOperation.recipient_id==player_id)).order_by(ItemOperation.created_at.desc()).limit(8)))
 related={o.serial for o in operations}
 instances=list(db.scalars(select(ItemInstance).where(or_(ItemInstance.owner_id==player_id,ItemInstance.beneficiary_id==player_id,ItemInstance.serial.in_(related))).order_by(ItemInstance.serial.desc()).limit(8)))
 wallet_ok=service_status(db)['available'];eq=db.get(RelicEquipment,player_id);items=[];equipped=None
 for i in instances:
  kind=db.get(Item,i.type_id);allowed=usable(db,i,player_id)
  reason='available' if allowed else 'belongs_to_another_player' if i.owner_id and i.owner_id!=player_id else 'reserved_or_pending' if i.state!='owned' else 'wallet_service_offline' if not wallet_ok else 'ownership_verification_stale'
  entry={'instance':i.serial,'name':kind.name,'damage':kind.damage,'rarity':kind.rarity,'state':i.state,'belongs_to_you':i.owner_id==player_id,'can_equip':allowed,'reason':reason,'equipped':bool(eq and eq.serial==i.serial and allowed)}
  if entry['equipped']:equipped={'instance':i.serial,'name':kind.name,'damage':kind.damage}
  items.append(entry)
 ordinary=[]
 for row in db.scalars(select(InventoryEntry).where(InventoryEntry.player_id==player_id,InventoryEntry.rgb_asset_id.is_(None)).limit(8)):
  item=db.get(Item,row.item_id)
  if item.id=='oath_relic':continue # Pending delivery is represented by the instance, not spendable inventory.
  ordinary.append({'name':item.name,'damage':item.damage,'quantity':row.quantity})
 trial=db.scalar(select(GameSession).where(GameSession.player_id==player_id).order_by(GameSession.created_at.desc()).limit(1))
 facts={'server_inventory':ordinary,'rgb_items':items,'rgb_equipped':equipped,'wallet_service_available':wallet_ok,
        'transfers':[{'instance':o.serial,'kind':o.kind,'state':o.state,'has_error':bool(o.error_code)} for o in operations],
        'trial':{k:trial.state.get(k) for k in ('status','hp','enemy_hp','stamina','intent','turn')} if trial else None,
        'scope':'Only the current visitor. At most 8 recent items and operations; missing records are unknown.'}
 if campaign:
  c=campaign.model_dump();weapon=LOCAL_ITEMS[c['weapon']]
  facts['campaign']={'source':'client-reported local save; not proof of RGB ownership','health':c['health'],'stamina':c['stamina'],'gold':c['gold'],'potions':c['potions'],
   'inventory':[LOCAL_ITEMS[k] for k in c['inventory']], 'weapon':weapon,'armor':LOCAL_ITEMS.get(c['armor']),
   'effective_damage':equipped['damage'] if equipped else weapon['damage']}
 else:facts['campaign']=None
 return facts

class QvacClient:
 def __init__(self):
  self.base='http://127.0.0.1:'+os.getenv('RUNEFORGE_QVAC_PORT','8790')
  self.key_path=Path(__file__).resolve().parents[3]/'.state/npc/service.key'
 def headers(self):
  try:return {'Authorization':'Bearer '+self.key_path.read_text().strip()}
  except OSError:return {}
 async def health(self):
  try:
   async with httpx.AsyncClient(trust_env=False,timeout=1.5) as client:
    r=await client.get(self.base+'/health');r.raise_for_status();data=r.json()
   if data.get('application')!='runeforge-blacksmith-qvac':raise ValueError()
   return {k:data.get(k) for k in ('state','model','provider','local','progress','downloaded','total','error')}
  except (httpx.HTTPError,ValueError):return {'state':'offline','model':MODEL,'provider':'qvac','local':True,'progress':None,'error':'service_offline'}
 async def load(self):
  try:
   async with httpx.AsyncClient(trust_env=False,timeout=2) as client:
    r=await client.post(self.base+'/load',headers=self.headers());r.raise_for_status()
  except httpx.HTTPError:raise RuntimeError('service_offline') from None
 async def reply(self,payload):
  try:
   async with httpx.AsyncClient(trust_env=False,timeout=70) as client:
    r=await client.post(self.base+'/reply',headers=self.headers(),json=payload)
   data=r.json()
   if r.status_code!=200:raise RuntimeError(data.get('error') if data.get('error') in ERRORS else 'inference_failed')
   if data.get('provider')!='qvac' or data.get('model')!=MODEL or data.get('local') is not True or not isinstance(data.get('reply'),str) or not 1<=len(data['reply'])<=600 or not isinstance(data.get('duration_ms'),int) or data['duration_ms']<0:raise RuntimeError('invalid_response')
   return data
  except httpx.TimeoutException:raise RuntimeError('inference_timeout') from None
  except (httpx.HTTPError,ValueError):raise RuntimeError('service_offline') from None

class Blacksmith:
 def __init__(self,session):self.Session=session;self.client=QvacClient();self.tasks={}
 def recover(self):
  with self.Session() as db:
   for row in db.scalars(select(NPCMessage).where(NPCMessage.status.in_(('queued','generating')))):
    row.status='failed';row.error_code='server_restarted'
   db.commit()
 async def close(self):
  tasks=list(self.tasks.values())
  for task in tasks:task.cancel()
  if tasks:await asyncio.gather(*tasks,return_exceptions=True)
 def launch(self,mid,payload):
  if mid in self.tasks:return
  task=asyncio.create_task(self.generate(mid,payload));self.tasks[mid]=task
  task.add_done_callback(lambda _:self.tasks.pop(mid,None))
 async def generate(self,mid,payload):
  result=None;error=None
  try:
   with self.Session() as db:
    row=db.get(NPCMessage,mid)
    if not row:return
    row.status='generating';db.commit()
   result=await self.client.reply(payload)
  except asyncio.CancelledError:error='cancelled'
  except Exception as exc:error=str(exc) if str(exc) in ERRORS else 'inference_failed'
  with self.Session() as db:
   row=db.get(NPCMessage,mid)
   if not row:return # Clear history must never be undone by a late model response.
   conversation=db.get(NPCConversation,row.player_id)
   if not conversation or conversation.revision!=row.revision:return
   if result:
    row.reply=result['reply'];row.model=result['model'];row.duration_ms=result['duration_ms'];row.status='completed';row.error_code=None
   else:row.status='failed';row.error_code=error
   db.commit()
