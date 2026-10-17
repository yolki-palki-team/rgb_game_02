import hashlib, os, secrets, time
from contextlib import asynccontextmanager
from typing import Literal
from fastapi import FastAPI, Depends, HTTPException, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field, ConfigDict
from sqlalchemy import select, func, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import IntegrityError
from .database import make_engine, seed
from .models import Base, Player, GameSession, Item, InventoryEntry, Equipment, LootReward, CommandReceipt, RGBAsset, RGBTransfer
from .combat.engine import initial, advance
from .services.rewards import ensure_reward
from .api.managed import install as install_managed
from .models import ManagedWallet,ItemInstance

class StrictModel(BaseModel):model_config=ConfigDict(extra='forbid')
class Registration(StrictModel):
 is_test:bool=False
 name:str=Field(min_length=1,max_length=32,pattern=r'^[\w .\-]+$')
 registration_key:str|None=Field(default=None,pattern=r'^[0-9a-f]{64}$')
class Command(StrictModel):
 action:Literal['attack','guard','rest']
 turn:int=Field(ge=0,le=60)
 idempotency_key:str=Field(min_length=8,max_length=128)
class Claim(StrictModel):idempotency_key:str=Field(min_length=8,max_length=128)
class Equip(StrictModel):inventory_id:str=Field(min_length=1,max_length=36)
class Withdraw(Claim):
 asset_id:str=Field(min_length=1,max_length=200)
 recipient:str=Field(min_length=8,max_length=2048)

bearer=HTTPBearer(auto_error=False)
def create_app(database_url=None,testing=False):
 engine=make_engine(database_url)
 Session=sessionmaker(engine,expire_on_commit=False)
 @asynccontextmanager
 async def lifespan(app):
  # SQLite is a zero-configuration local fallback. PostgreSQL uses Alembic.
  if engine.dialect.name=='sqlite':Base.metadata.create_all(engine)
  seed(engine)
  yield
  engine.dispose()
 app=FastAPI(title='RuneForge',version='1.0.0',lifespan=lifespan)
 app.state.engine=engine
 def db_session():
  with Session() as db:
   try:yield db
   except:db.rollback();raise
 def auth(credentials:HTTPAuthorizationCredentials|None=Depends(bearer),db=Depends(db_session)):
  if not credentials:raise HTTPException(401,'Bearer token required')
  player=db.scalar(select(Player).where(Player.token_hash==hashlib.sha256(credentials.credentials.encode()).hexdigest()))
  if not player:raise HTTPException(401,'Invalid token')
  return player
 def lock_player(db,p):
  # A per-player DB lock serializes reward, equipment, and session mutations.
  # SQLite BEGIN IMMEDIATE serializes writers; PostgreSQL uses row-level locking.
  if engine.dialect.name=='sqlite':
   db.rollback();db.execute(text('BEGIN IMMEDIATE'))
  return db.scalar(select(Player).where(Player.id==p.id).with_for_update())
 def get_session(db,p,sid):
  row=db.scalar(select(GameSession).where(GameSession.id==sid,GameSession.player_id==p.id).with_for_update())
  if not row:raise HTTPException(404,'Session not found')
  return row
 def state(row):return {'id':row.id,**row.state}
 def count(db,p):return db.scalar(select(func.count()).select_from(InventoryEntry).where(InventoryEntry.player_id==p.id))
 def transfer_json(r):return dict(id=r.id,asset_id=r.asset_id,state=r.state,mode=r.mode,txid=r.txid)
 @app.get('/health')
 def health(db=Depends(db_session)):
  db.execute(text('SELECT 1'));return {'status':'ok','application':'runeforge-managed-v2','database':engine.dialect.name,'rgb_mode':'real','network':'regtest'}
 @app.post('/api/players',status_code=201)
 def register(body:Registration,db=Depends(db_session)):
  token=hashlib.sha256(('runeforge-local-profile:'+body.registration_key).encode()).hexdigest() if body.registration_key else secrets.token_urlsafe(32)
  digest=hashlib.sha256(token.encode()).hexdigest()
  existing=db.scalar(select(Player).where(Player.token_hash==digest))
  if existing:
   if existing.name!=body.name or existing.is_test!=body.is_test:raise HTTPException(409,'Registration key already used')
   return {'id':existing.id,'name':existing.name,'token':token}
  try:
   p=Player(name=body.name,is_test=body.is_test,token_hash=hashlib.sha256(token.encode()).hexdigest());db.add(p);db.flush()
   db.add(InventoryEntry(player_id=p.id,item_id='warden_iron'));db.add(ManagedWallet(player_id=p.id));db.commit()
  except IntegrityError:
   db.rollback()
   p=db.scalar(select(Player).where(Player.token_hash==digest))
   if not p or p.name!=body.name or p.is_test!=body.is_test:raise HTTPException(409,'Registration conflict') from None
  return {'id':p.id,'name':p.name,'token':token}
 @app.get('/api/profile')
 def profile(p=Depends(auth)):return {'id':p.id,'name':p.name}
 @app.get('/api/inventory')
 def inventory(p=Depends(auth),db=Depends(db_session)):
  entries=db.scalars(select(InventoryEntry).where(InventoryEntry.player_id==p.id)).all()
  return {'items':[dict(id=e.id,item_id=e.item_id,name=db.get(Item,e.item_id).name,quantity=e.quantity,rgb_asset_id=e.rgb_asset_id,ownership=(db.get(RGBAsset,e.rgb_asset_id).ownership if e.rgb_asset_id and db.get(RGBAsset,e.rgb_asset_id) else 'gameplay_only')) for e in entries]}
 @app.get('/api/equipment')
 def equipment(p=Depends(auth),db=Depends(db_session)):
  return {'slots':{e.slot:e.inventory_id for e in db.scalars(select(Equipment).where(Equipment.player_id==p.id))}}
 @app.post('/api/equipment')
 def equip(body:Equip,p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p)
  entry=db.get(InventoryEntry,body.inventory_id)
  if not entry or entry.player_id!=p.id:raise HTTPException(404,'Inventory entry not found')
  if entry.rgb_asset_id or entry.item_id=='oath_relic':
   raise HTTPException(409,'Use the verified managed-item equipment endpoint')
  slot=db.get(Item,entry.item_id).slot
  eq=db.scalar(select(Equipment).where(Equipment.player_id==p.id,Equipment.slot==slot))
  if eq:eq.inventory_id=entry.id
  else:db.add(Equipment(player_id=p.id,slot=slot,inventory_id=entry.id))
  db.commit();return {'slot':slot,'inventory_id':entry.id}
 @app.post('/api/sessions',status_code=201)
 def begin(p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p)
  # Reconnect to the one active trial, rather than orphaning it on retry.
  for row in db.scalars(select(GameSession).where(GameSession.player_id==p.id).order_by(GameSession.created_at.desc())):
   if row.state['status']=='active':db.commit();return state(row)
  row=GameSession(player_id=p.id,state=initial());db.add(row);db.commit();return state(row)
 @app.get('/api/sessions/{sid}')
 def session(sid:str,p=Depends(auth),db=Depends(db_session)):return state(get_session(db,p,sid))
 @app.post('/api/sessions/{sid}/commands')
 def command(sid:str,body:Command,p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p);row=get_session(db,p,sid)
  existing=db.scalar(select(CommandReceipt).where(CommandReceipt.session_id==sid,CommandReceipt.key==body.idempotency_key))
  if existing:
   if existing.turn!=body.turn or existing.action!=body.action:raise HTTPException(409,'Idempotency key reused with different command')
   return existing.result
  if row.state['turn']!=body.turn:raise HTTPException(409,'Stale command; reload session')
  current=time.time()
  if not testing and current-row.last_action<0.35:raise HTTPException(429,'Action cooldown; retry the same command')
  try:row.state=advance(row.state,body.action)
  except ValueError as exc:raise HTTPException(409,str(exc))
  row.last_action=current
  if row.state['status']=='won':ensure_reward(db,p.id,sid,'victory-'+sid)
  result=state(row)
  db.add(CommandReceipt(session_id=sid,key=body.idempotency_key,turn=body.turn,action=body.action,result=result));db.commit();return result
 @app.post('/api/sessions/{sid}/result')
 def reward(sid:str,body:Claim,p=Depends(auth),db=Depends(db_session)):
  lock_player(db,p);row=get_session(db,p,sid)
  key=db.scalar(select(LootReward).where(LootReward.player_id==p.id,LootReward.idempotency_key==body.idempotency_key))
  if key and key.session_id!=sid:raise HTTPException(409,'Reward key already used for another session')
  existing=db.scalar(select(LootReward).where(LootReward.session_id==sid))
  if row.state['status']!='won':raise HTTPException(409,'Victory has not been validated by the server')
  existing,instance=ensure_reward(db,p.id,sid,body.idempotency_key)
  total=count(db,p);db.commit()
  return {'reward_id':existing.id,'inventory_id':existing.inventory_id,'inventory_count':total,'serial':instance.serial if instance else None,'message':'Reward earned. The smith is issuing your sword and delivering it to your wallet.'}
 @app.get('/api/ownership/{asset_id}')
 def ownership(asset_id:str,p=Depends(auth),db=Depends(db_session)):
  asset=db.get(RGBAsset,asset_id)
  if not asset or asset.player_id!=p.id:raise HTTPException(404,'Asset not linked to this profile')
  return {'asset_id':asset.asset_id,'mode':asset.mode,'ownership':asset.ownership,'equippable':False}
 @app.get('/api/vault')
 def vault(p=Depends(auth),db=Depends(db_session)):
  mode='real'
  assets=db.scalars(select(RGBAsset).where(RGBAsset.player_id==p.id)).all()
  transfers=db.scalars(select(RGBTransfer).where(RGBTransfer.player_id==p.id).order_by(RGBTransfer.created_at.desc())).all()
  return {'mode':mode,'inventory_count':count(db,p),'summary':'Managed real regtest wallets. Use /api/relics for live ownership and item operations.','assets':[{'asset_id':a.asset_id,'ownership':a.ownership,'category':a.category} for a in assets],'transfers':[transfer_json(r) for r in transfers]}
 @app.post('/api/rgb/receive')
 def receive(p=Depends(auth)):
  raise HTTPException(410,'Invoices are handled automatically by the managed-item worker.')
 @app.post('/api/rgb/transfers',status_code=202)
 def withdraw(body:Withdraw,p=Depends(auth),db=Depends(db_session)):
  raise HTTPException(410,'External withdrawals disabled; choose a managed player in /api/relics/{serial}/transfer')
 @app.get('/api/rgb/transfers')
 def transfers(p=Depends(auth),db=Depends(db_session)):
  return {'transfers':[transfer_json(r) for r in db.scalars(select(RGBTransfer).where(RGBTransfer.player_id==p.id))]}
 install_managed(app,db_session,auth,lock_player)
 return app

app=create_app()
