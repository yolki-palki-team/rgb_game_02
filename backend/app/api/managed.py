"""Player-facing managed item API. No client-supplied contract can establish ownership."""
import time
from typing import Literal
from fastapi import Depends, HTTPException
from pydantic import BaseModel,ConfigDict,Field
from sqlalchemy import select,or_,delete
from ..models import (Player,ManagedWallet,ItemInstance,ItemOperation,ItemEvent,WorkerState,
                      RelicEquipment,Item,GameSession,InventoryEntry,LootReward)

LEASE_SECONDS=4.0
VERIFY_SECONDS=8.0
HEARTBEAT_SECONDS=8.0

class TransferRequest(BaseModel):
 model_config=ConfigDict(extra='forbid')
 recipient_id:str=Field(min_length=36,max_length=36)
 idempotency_key:str=Field(min_length=8,max_length=128)
 confirm:Literal[True]

LABELS={
 'earned':'Reward earned','issuing':'Smith is issuing your unique sword',
 'preparing':'Preparing to receive','delivering':'Delivering the sword to your wallet',
 'requested':'Item reserved','signing':'Submitting transfer',
 'waiting_counterparty':'Recipient is validating the item','waiting_safe_height':'Waiting for a safe block height',
 'waiting_broadcast':'Waiting for transaction broadcast','waiting_confirmations':'Waiting for Bitcoin confirmation',
 'waiting_receiver':'Verifying receipt in the wallet','settled':'Item received','owned':'Ownership verified','transferring':'Item is being transferred',
 'recovery_required':'Checking interrupted operation','verification_required':'Checking wallet',
 'failed':'Transfer incomplete; ownership rechecked'
}
def profile_label(name):
 # Localize only legacy built-in labels; never rename users or change registration data.
 labels={}
 for slot in ('A','B'):
  labels['\u0418\u0433\u0440\u043e\u043a '+slot]='Player '+slot
  labels['\u0422\u0435\u0441\u0442 '+slot]='Test '+slot
  for client in ('JS','WASM'):
   labels['\u0422\u0435\u0441\u0442 '+client+' '+slot]='Test '+client+' '+slot
 return labels.get(name,name)

def service_status(db):
 row=db.get(WorkerState,'managed')
 ok=bool(row and row.available and time.time()-row.heartbeat<HEARTBEAT_SECONDS)
 return {'available':ok,'mode':'real','network':'regtest','custody':'The local RuneForge service holds the keys to separate player wallets.',
         'message':'Wallets connected · Bitcoin regtest' if ok else 'Wallet service or RGB infrastructure is offline. Items are temporarily unavailable.',
         'error_code':None if ok else (row.error_code if row else 'worker_offline'),'block_height':row.block_height if row else None}

def usable(db,i,pid):
 return bool(i and i.owner_id==pid and i.asset_id and i.state=='owned' and time.time()-i.verified_at<VERIFY_SECONDS and service_status(db)['available'])

def install(app,db_session,auth,lock_player):
 def locked_instance(db,serial):
  return db.scalar(select(ItemInstance).where(ItemInstance.serial==serial).with_for_update())
 def require_ready(db):
  if not service_status(db)['available']:raise HTTPException(503,'Wallets are unavailable. Wait for the connection to recover; transfers are never simulated.')
 @app.get('/api/relics')
 def relics(p=Depends(auth),db=Depends(db_session)):
  # The same instance row lock serializes lease renewal and transfer reservation.
  lock_player(db,p)
  if not db.get(ManagedWallet,p.id):db.add(ManagedWallet(player_id=p.id));db.flush()
  status=service_status(db)
  ops=db.scalars(select(ItemOperation).where(or_(ItemOperation.requester_id==p.id,ItemOperation.recipient_id==p.id)).order_by(ItemOperation.created_at.desc())).all()
  related={o.serial for o in ops}
  instances=db.scalars(select(ItemInstance).where(or_(ItemInstance.owner_id==p.id,ItemInstance.beneficiary_id==p.id,ItemInstance.serial.in_(related))).order_by(ItemInstance.serial.desc()).with_for_update()).all()
  eq=db.get(RelicEquipment,p.id)
  equipment=None
  items=[]
  for i in instances:
   t=db.get(Item,i.type_id);allowed=usable(db,i,p.id)
   equipped=bool(eq and eq.serial==i.serial and allowed)
   if equipped:
    # Grant an absolute expiry, bounded by the freshness of the observed SDK state.
    i.use_until=min(time.time()+LEASE_SECONDS,i.verified_at+VERIFY_SECONDS)
    equipment={'serial':i.serial,'name':t.name,'damage':t.damage,'lease_until':i.use_until,'asset_id':i.asset_id}
   items.append(dict(serial=i.serial,type_id=t.id,name=t.name,damage=t.damage,rarity=t.rarity,slot=t.slot,description=t.description,
    asset_id=i.asset_id,state=i.state,status=LABELS.get(i.state,i.state),owner_id=i.owner_id,is_owner=i.owner_id==p.id,
    can_equip=allowed,equipped=equipped,revision=i.revision,verified_at=i.verified_at))
  if eq and equipment is None:db.delete(eq)
  profiles=db.scalars(select(Player).join(ManagedWallet,ManagedWallet.player_id==Player.id).where(Player.is_test==p.is_test).order_by(Player.created_at.desc()).limit(100)).all()
  history=[]
  for o in ops[:20]:
   history.append(dict(id=o.id,serial=o.serial,kind=o.kind,state=o.state,status=LABELS.get(o.state,o.state),recipient_id=o.recipient_id,
    recipient_name=profile_label(db.get(Player,o.recipient_id).name),txid=o.txid,error_code=o.error_code,
    events=[{'state':e.state,'status':LABELS.get(e.state,e.state)} for e in db.scalars(select(ItemEvent).where(ItemEvent.operation_id==o.id).order_by(ItemEvent.id))]))
  last=db.scalar(select(GameSession).where(GameSession.player_id==p.id).order_by(GameSession.created_at.desc()).limit(1))
  trial={'id':last.id,**last.state} if last else None
  db.commit()
  return dict(profile={'id':p.id,'name':profile_label(p.name),'is_test':p.is_test},service=status,items=items,equipment=equipment,history=history,
              players=[dict(id=q.id,name=profile_label(q.name)) for q in profiles if q.id!=p.id],trial=trial,server_time=time.time())
 @app.post('/api/relics/{serial}/equip')
 def equip(serial:int,p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p);require_ready(db);i=locked_instance(db,serial)
  if not usable(db,i,p.id):raise HTTPException(409,'This sword is not in your wallet, is reserved, or is still being verified.')
  eq=db.get(RelicEquipment,p.id)
  if eq:eq.serial=serial
  else:db.add(RelicEquipment(player_id=p.id,serial=serial))
  db.commit();return {'message':'Sword equipped. Stats updated by the server.'}
 @app.delete('/api/relics/equipment')
 def unequip(p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p);db.execute(delete(RelicEquipment).where(RelicEquipment.player_id==p.id));db.commit()
  return {'message':'Campaign weapon equipped.'}
 @app.post('/api/relics/{serial}/transfer',status_code=202)
 def transfer(serial:int,body:TransferRequest,p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p)
  prior=db.scalar(select(ItemOperation).where(ItemOperation.requester_id==p.id,ItemOperation.request_key==body.idempotency_key))
  if prior:
   if prior.serial!=serial or prior.recipient_id!=body.recipient_id:raise HTTPException(409,'This request key was already used for another transfer.')
   return {'id':prior.id,'state':prior.state,'message':LABELS.get(prior.state,prior.state)}
  require_ready(db);i=locked_instance(db,serial)
  if not usable(db,i,p.id):raise HTTPException(409,'This item cannot be transferred or belongs to another player.')
  if body.recipient_id==p.id:raise HTTPException(409,'Choose another player.')
  receiver=db.get(Player,body.recipient_id)
  if not receiver or receiver.is_test!=p.is_test or not db.get(ManagedWallet,body.recipient_id):raise HTTPException(404,'Recipient unavailable. Test profiles are separate from regular players.')
  i.state='transferring';i.verified_at=0;i.revision+=1
  db.execute(delete(RelicEquipment).where(RelicEquipment.serial==serial))
  op=ItemOperation(serial=serial,kind='transfer',requester_id=p.id,sender_id=p.id,recipient_id=body.recipient_id,request_key=body.idempotency_key,state='requested')
  db.add(op);db.flush();db.add(ItemEvent(operation_id=op.id,state='requested'));db.commit()
  return {'id':op.id,'state':op.state,'message':'Sword unequipped and reserved. Transfer is running automatically.'}
