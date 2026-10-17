"""DB authorization/lease tests use explicit synthetic fixtures, never RGB integration evidence."""
import time
from concurrent.futures import ThreadPoolExecutor
from sqlalchemy.orm import Session
from sqlalchemy import select,func
from .test_api import api,win
from backend.app.models import ItemInstance,ItemOperation,RGBAsset,WorkerState,RelicEquipment

def earned(api):
 trial=win(api)
 with Session(api.app.state.engine) as db:
  i=db.scalar(select(ItemInstance).where(ItemInstance.beneficiary_id==api.player_id))
  return i.serial

def authorize_fixture(api,serial):
 with Session(api.app.state.engine) as db:
  i=db.get(ItemInstance,serial)
  db.add(RGBAsset(asset_id='test-only-contract',category='UDA',item_id=i.type_id,player_id=api.player_id,mode='real',ownership='verified_managed_wallet'))
  db.flush();i.asset_id='test-only-contract';i.owner_id=api.player_id;i.state='owned';i.verified_at=time.time()
  db.add(WorkerState(id='managed',heartbeat=time.time(),available=1));db.commit()

def test_automatic_reward_and_unverified_rejection(api):
 serial=earned(api)
 with Session(api.app.state.engine) as db:
  assert db.scalar(select(func.count()).select_from(ItemOperation))==1
  assert db.get(ItemInstance,serial).state=='earned'
 assert api.post(f'/api/relics/{serial}/equip').status_code==503
 data=api.get('/api/relics').json()
 assert data['items'][0]['asset_id'] is None and not data['items'][0]['can_equip']

def test_atomic_reservation_and_lease(api):
 serial=earned(api);authorize_fixture(api,serial)
 receiver=api.post('/api/players',json={'name':'Recipient'}).json()
 assert api.post(f'/api/relics/{serial}/equip').status_code==200
 eq=api.get('/api/relics').json()['equipment']
 assert eq['damage']==52 and time.time()<eq['lease_until']<=time.time()+4
 url=f'/api/relics/{serial}/transfer'
 def transfer(n):return api.post(url,json={'recipient_id':receiver['id'],'confirm':True,'idempotency_key':f'transfer-{n:04}'})
 with ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(transfer,range(3)))
 assert sorted(r.status_code for r in results)==[202,409,409]
 assert api.get('/api/relics').json()['equipment'] is None
 assert api.post(f'/api/relics/{serial}/equip').status_code==409
 with Session(api.app.state.engine) as db:
  i=db.get(ItemInstance,serial)
  assert i.state=='transferring' and i.use_until==eq['lease_until']
  assert db.scalar(select(func.count()).select_from(ItemOperation).where(ItemOperation.kind=='transfer'))==1

def test_old_evidence_cannot_authorize(api):
 serial=earned(api);authorize_fixture(api,serial)
 with Session(api.app.state.engine) as db:
  db.get(ItemInstance,serial).verified_at=time.time()-9;db.commit()
 assert api.post(f'/api/relics/{serial}/equip').status_code==409
 with Session(api.app.state.engine) as db:
  db.get(ItemInstance,serial).verified_at=time.time();db.get(WorkerState,'managed').heartbeat=time.time()-9;db.commit()
 assert api.post(f'/api/relics/{serial}/equip').status_code==503

def test_asset_id_cannot_grant_access(api):
 serial=earned(api);authorize_fixture(api,serial)
 other=api.post('/api/players',json={'name':'Other'}).json()
 headers={'Authorization':'Bearer '+other['token']}
 assert api.post(f'/api/relics/{serial}/equip',headers=headers).status_code==409
 assert api.post(f'/api/relics/{serial}/transfer',json={'recipient_id':other['id'],'confirm':True,'idempotency_key':'forged-id','asset_id':'test-only-contract'}).status_code==422
 assert api.post('/api/relics',json={'asset_id':'test-only-contract'}).status_code==405

def test_sender_settlement_waits_for_receiver_and_old_lease(api):
 from types import SimpleNamespace
 from backend.app.services.worker import Worker,TERMINAL
 serial=earned(api);authorize_fixture(api,serial)
 with Session(api.app.state.engine) as db:
  i=db.get(ItemInstance,serial);i.owner_id=None;i.state='delivering';i.use_until=time.time()+10
  op=db.scalar(select(ItemOperation).where(ItemOperation.serial==serial));op.invoice='unit-test-only';op.txid='unit-test-only';op.batch_idx=7;op.state='waiting_confirmations';oid=op.id;db.commit()
 received=[{'state':'WAITING_CONFIRMATIONS','txid':'unit-test-only','batch_idx':3}]
 recipient=SimpleNamespace(refresh=lambda *_:received,balance=lambda _:dict(settled=1,spendable=1),r=SimpleNamespace(RgbLibError=SimpleNamespace(AssetNotFound=ValueError)))
 sender=SimpleNamespace(refresh=lambda _:[{'state':'SETTLED','txid':'unit-test-only','batch_idx':7}],balance=lambda _:dict(settled=0,spendable=0))
 w=Worker.__new__(Worker);w.engine=api.app.state.engine;w.prepare=lambda pid:recipient if pid else sender
 w.process(oid)
 with Session(w.engine) as db:
  assert db.get(ItemOperation,oid).state=='waiting_receiver'
  assert db.get(ItemOperation,oid).state not in TERMINAL
  assert db.get(ItemInstance,serial).owner_id is None
 received[0]['state']='SETTLED';w.process(oid)
 with Session(w.engine) as db:
  i=db.get(ItemInstance,serial);assert i.owner_id is None
  i.use_until=0;db.commit()
 w.process(oid)
 with Session(w.engine) as db:
  assert db.get(ItemOperation,oid).state=='settled'
  assert db.get(ItemInstance,serial).owner_id==api.player_id

def test_recipient_purpose_is_server_enforced_not_name_based(api):
 ordinary=api.post('/api/players',json={'name':'Test is only a name'}).json()
 automated=api.post('/api/players',json={'name':'Player A','is_test':True}).json()
 listing=api.get('/api/relics').json()['players']
 assert ordinary['id'] in {p['id'] for p in listing}
 assert automated['id'] not in {p['id'] for p in listing}
 test_headers={'Authorization':'Bearer '+automated['token']}
 test_listing=api.get('/api/relics',headers=test_headers).json()
 assert test_listing['profile']['is_test'] is True
 assert api.player_id not in {p['id'] for p in test_listing['players']}
 serial=earned(api);authorize_fixture(api,serial)
 body={'recipient_id':automated['id'],'confirm':True,'idempotency_key':'hidden-recipient'}
 assert api.post(f'/api/relics/{serial}/transfer',json=body).status_code==404
 with Session(api.app.state.engine) as db:
  assert db.get(ItemInstance,serial).state=='owned'
  assert db.scalar(select(func.count()).select_from(ItemOperation).where(ItemOperation.kind=='transfer'))==0

def test_registration_cannot_reclassify_existing_profile(api):
 body={'name':'Purpose','registration_key':'b'*64,'is_test':True}
 first=api.post('/api/players',json=body)
 assert first.status_code==201
 assert api.post('/api/players',json=body).json()==first.json()
 assert api.post('/api/players',json={**body,'is_test':False}).status_code==409


def test_english_catalog_preserves_item_identity_and_ownership(api):
 from backend.app.database import seed
 from backend.app.models import Item
 serial=earned(api);authorize_fixture(api,serial)
 with Session(api.app.state.engine) as db:
  item=db.get(Item,'oath_relic');item.name='\u041e\u0433\u043d\u0435\u043d\u043d\u044b\u0439 \u043c\u0435\u0447';db.commit()
  instance=db.get(ItemInstance,serial);before=(instance.asset_id,instance.owner_id,instance.state)
 seed(api.app.state.engine)
 with Session(api.app.state.engine) as db:
  instance=db.get(ItemInstance,serial)
  assert (instance.asset_id,instance.owner_id,instance.state)==before
  assert db.get(Item,'oath_relic').name=='Flame Sword'
 data=api.get('/api/relics').json()
 assert data['items'][0]['status']=='Ownership verified'
 assert data['items'][0]['name']=='Flame Sword'
 assert data['service']['message']=='Wallets connected · Bitcoin regtest'


def test_legacy_profile_labels_do_not_change_registration(api):
 from backend.app.api.managed import profile_label
 name='\u0418\u0433\u0440\u043e\u043a A'
 body={'name':name,'registration_key':'e'*64}
 first=api.post('/api/players',json=body).json()
 assert api.post('/api/players',json=body).json()['id']==first['id']
 headers={'Authorization':'Bearer '+first['token']}
 assert api.get('/api/profile',headers=headers).json()['name']==name
 assert api.get('/api/relics',headers=headers).json()['profile']['name']=='Player A'
 assert profile_label('Custom name')=='Custom name'
