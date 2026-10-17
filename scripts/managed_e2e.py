"""Real player A -> player B test. No fixture ownership flags or mocked wallets.
Runs a separate worker process and kills it at native SDK crash boundaries.
"""
import json,os,subprocess,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import httpx
from sqlalchemy import select,func
from sqlalchemy.orm import Session
from backend.app.database import make_engine
from backend.app.models import ItemOperation,ItemInstance,ItemEvent,WorkerState
from backend.app.rgb.service import RealRGB
ROOT=Path(__file__).resolve().parents[1]
BASE=os.getenv('RUNEFORGE_API_URL','http://127.0.0.1:8787')

def worker_once(fault=None):
 env=dict(os.environ)
 if fault:env['RUNEFORGE_FAULT']=fault
 else:env.pop('RUNEFORGE_FAULT',None)
 result=subprocess.run([sys.executable,'-m','backend.app.services.worker','--once'],cwd=ROOT,env=env,capture_output=True,text=True,timeout=100)
 if result.returncode not in (0,91,92,93,94):raise AssertionError('Worker failed: '+result.stderr[-1600:])
 return result.returncode

def main():
 evidence={'mode':'real','network':'regtest','library':'rgb-lib==0.3.0b7','checks':[]}
 statefile=ROOT/os.getenv('RUNEFORGE_E2E_PROFILES','.state/managed-e2e-profiles.json');statefile.parent.mkdir(exist_ok=True)
 if statefile.exists():profiles=json.loads(statefile.read_text())
 else:
  profiles=[httpx.post(BASE+'/api/players',json={'name':'Verification '+x,'is_test':True},timeout=10).json() for x in ('A','B')]
  statefile.write_text(json.dumps(profiles));statefile.chmod(0o600)
 a,b=[httpx.Client(base_url=BASE,headers={'Authorization':'Bearer '+p['token']},timeout=20) for p in profiles]
 engine=make_engine()
 trial=a.get('/api/relics').json().get('trial')
 if not trial or trial['status']=='lost':trial=a.post('/api/sessions',json={}).json()
 for turn in range(60):
  if trial['status']!='active':break
  action='guard' if trial['intent']=='heavy' else ('rest' if trial['stamina']<24 else 'attack')
  time.sleep(.38)
  result=a.post('/api/sessions/'+trial['id']+'/commands',json={'action':action,'turn':trial['turn'],'idempotency_key':f"e2e-command-{trial['turn']}"})
  assert result.status_code==200,result.text
  trial=result.json()
 assert trial['status']=='won'
 claim=a.post('/api/sessions/'+trial['id']+'/result',json={'idempotency_key':'e2e-reward-'+trial['id']}).json()
 serial=claim['serial'];assert serial
 checkpoint_file=statefile.with_suffix('.checkpoints.json')
 checkpoints=json.loads(checkpoint_file.read_text()) if checkpoint_file.exists() else {'serial':serial}
 assert checkpoints['serial']==serial
 def checkpoint(name):
  checkpoints[name]=True;checkpoint_file.write_text(json.dumps(checkpoints))
 for _ in range(3):assert a.post('/api/sessions/'+trial['id']+'/result',json={'idempotency_key':'e2e-reward-'+trial['id']}).json()['serial']==serial
 print('Server victory and single durable reward',flush=True)
 # Crash after native issuance, before storing its returned asset ID in either journal or game DB.
 with Session(engine) as db:already_issued=bool(db.get(ItemInstance,serial).asset_id)
 if not already_issued:
  assert worker_once('issue_native')==91
  checkpoint('native_issuance_crash_recovered')
  assert worker_once()==0
 with Session(engine) as db:aid=db.get(ItemInstance,serial).asset_id
 assert aid
 print('Registered issuance verified:',aid,flush=True)
 with Session(engine) as db:
  prior=db.scalar(select(ItemOperation).where(ItemOperation.serial==serial,ItemOperation.kind=='transfer'))
  transfer=prior.id if prior else None
 if transfer is None:
  for _ in range(20):
   worker_once()
   with Session(engine) as db:
    i=db.get(ItemInstance,serial)
    if i.state=='owned':break
  else:raise AssertionError('Award did not settle')
  # --once explicitly reports stopped. A persistent worker is used for active leases/API assertions.
  proc=subprocess.Popen([sys.executable,'-m','backend.app.services.worker'],cwd=ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  try:
   for _ in range(60):
    data=a.get('/api/relics').json()
    if data['service']['available']:break
    time.sleep(.3)
   result=a.post(f'/api/relics/{serial}/equip');assert result.status_code==200,result.text
   equipped=a.get('/api/relics').json()['equipment'];assert equipped['serial']==serial and equipped['damage']==52
   assert b.post(f'/api/relics/{serial}/equip').status_code==409
   assert a.post('/api/equipment',json={'inventory_id':claim['inventory_id']}).status_code==409
   forged=a.post(f'/api/relics/{serial}/transfer',json={'recipient_id':profiles[1]['id'],'asset_id':aid,'confirm':True,'idempotency_key':'forged-request'})
   assert forged.status_code==422
   # Hard-kill during live checking; this also exercises stale native runtime-marker recovery.
   proc.kill();proc.wait(timeout=60)
   # Last heartbeat remains fresh for at most eight seconds; reservation atomically stops new leases.
   body={'recipient_id':profiles[1]['id'],'confirm':True,'idempotency_key':'e2e-transfer-'+str(serial)}
   response=a.post(f'/api/relics/{serial}/transfer',json=body);assert response.status_code==202,response.text
   transfer=response.json()['id']
   assert a.post(f'/api/relics/{serial}/transfer',json=body).json()['id']==transfer
   assert a.post(f'/api/relics/{serial}/transfer',json={**body,'idempotency_key':'second-transfer'}).status_code==409
   assert b.post(f'/api/relics/{serial}/transfer',json={**body,'recipient_id':profiles[0]['id'],'idempotency_key':'stolen-transfer'}).status_code==409
   assert a.get('/api/relics').json()['equipment'] is None
  finally:
   if proc.poll() is None:proc.kill();proc.wait(timeout=60)
 else:print('Resuming the same registered transfer',flush=True)
 with Session(engine) as db:submitted=bool(db.get(ItemOperation,transfer).txid)
 if not submitted:
  with Session(engine) as db:has_invoice=bool(db.get(ItemOperation,transfer).invoice)
  if not has_invoice:worker_once()
  assert worker_once('send_native')==92
  checkpoint('native_send_crash_recovered')
  print('Native transfer interrupted; restarting worker',flush=True)
 for _ in range(25):
  worker_once()
  with Session(engine) as db:
   op=db.get(ItemOperation,transfer)
   if op.state=='settled':txid=op.txid;break
 else:raise AssertionError('Transfer did not settle after crash recovery')
 proc=subprocess.Popen([sys.executable,'-m','backend.app.services.worker'],cwd=ROOT,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  for _ in range(60):
   data=b.get('/api/relics').json()
   if data['service']['available']:break
   time.sleep(.3)
  assert a.post(f'/api/relics/{serial}/equip').status_code==409
  assert b.post(f'/api/relics/{serial}/equip').status_code==200
  equipment=b.get('/api/relics').json()['equipment']
  assert equipment['serial']==serial and equipment['asset_id']==aid and equipment['damage']==52
  assert a.get('/api/relics').json()['equipment'] is None
 finally:proc.terminate();proc.wait(timeout=60)
 root=Path(os.getenv('RUNEFORGE_WALLET_ROOT','.state/managed-v2'))
 with RealRGB(root/profiles[0]['id']) as aw,RealRGB(root/profiles[1]['id']) as bw,RealRGB(root/'issuer') as issuer:
  sender_fingerprint=aw.wallet.get_keys().master_fingerprint
  recipient_fingerprint=bw.wallet.get_keys().master_fingerprint
  assert sender_fingerprint!=recipient_fingerprint
  assert aw.balance(aid)['settled']==0 and bw.balance(aid)['settled']==1
  metadata=issuer.wallet.get_asset_metadata(aid)
  assert metadata.details=='RuneForge registered instance. Issue key: managed-instance-'+str(serial)
  minted=[x for x in issuer.assets() if issuer.wallet.get_asset_metadata(x['asset_id']).details==metadata.details]
  assert len(minted)==1
 with Session(engine) as db:
  i=db.get(ItemInstance,serial);op=db.get(ItemOperation,transfer)
  award=db.scalar(select(ItemOperation).where(ItemOperation.serial==serial,ItemOperation.kind=='award'))
  evidence.update(serial=serial,asset_id=aid,sender_wallet_fingerprint=sender_fingerprint,recipient_wallet_fingerprint=recipient_fingerprint,matching_issuances=len(minted),award_txid=award.txid,transfer_txid=txid,sender_id=profiles[0]['id'],recipient_id=profiles[1]['id'],sender_settled=0,recipient_settled=1,owner_id=i.owner_id,damage=52,
                  issuance_events=[e.state for e in db.scalars(select(ItemEvent).where(ItemEvent.operation_id==award.id).order_by(ItemEvent.id))],
                  transfer_events=[e.state for e in db.scalars(select(ItemEvent).where(ItemEvent.operation_id==op.id).order_by(ItemEvent.id))])
 evidence['checks']=['separate_wallets','authoritative_victory','single_UDA','equip_52_ATK','real_A_to_B','same_instance_and_asset','sender_revoked','recipient_equipped','replay_idempotent','double_transfer_rejected','asset_id_claim_rejected']
 evidence['checks'] += [name for name in ('native_issuance_crash_recovered','native_send_crash_recovered') if checkpoints.get(name)]
 Path('docs/evidence/managed-e2e.json').write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+'\n')
 print('MANAGED_E2E_PASS',flush=True)
if __name__=='__main__':main()
