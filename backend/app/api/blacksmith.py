"""Authenticated, non-blocking dialogue API. No model output is executed."""
from typing import Literal
from fastapi import Depends,HTTPException
from pydantic import BaseModel,ConfigDict,Field
from sqlalchemy import select,delete
from ..models import NPCConversation,NPCMessage
from ..services.blacksmith import Blacksmith,ERRORS,facts_for
class Campaign(BaseModel):
 model_config=ConfigDict(extra='forbid')
 health:float=Field(ge=0,le=100)
 stamina:float=Field(ge=0,le=100)
 gold:int=Field(ge=0,le=100000000)
 potions:int=Field(ge=0,le=1000000)
 inventory:list[Literal['iron','fang','rune','legendary','armor']]=Field(max_length=8)
 weapon:Literal['iron','fang','rune','legendary']
 armor:Literal['','armor']=''
class Message(BaseModel):
 model_config=ConfigDict(extra='forbid')
 text:str=Field(min_length=1,max_length=600)
 request_key:str=Field(pattern=r'^[a-zA-Z0-9_-]{16,64}$')
 revision:int=Field(ge=0)
 campaign:Campaign|None=None
class Clear(BaseModel):
 model_config=ConfigDict(extra='forbid')
 revision:int=Field(ge=0)

def message_json(row):return {'id':row.id,'request_key':row.request_key,'text':row.prompt,'reply':row.reply,'status':row.status,'error':ERRORS.get(row.error_code),'error_code':row.error_code,'model':row.model,'duration_ms':row.duration_ms}

def install(app,db_session,auth,lock_player,session):
 manager=Blacksmith(session);app.state.blacksmith=manager
 def conversation(db,p):
  lock_player(db,p)
  row=db.get(NPCConversation,p.id)
  if not row:row=NPCConversation(player_id=p.id,revision=0);db.add(row);db.flush()
  return row
 @app.get('/api/npc/blacksmith')
 async def history(p=Depends(auth),db=Depends(db_session)):
  conv=conversation(db,p);revision=conv.revision
  rows=list(db.scalars(select(NPCMessage).where(NPCMessage.player_id==p.id,NPCMessage.revision==revision).order_by(NPCMessage.created_at.desc()).limit(12)))
  messages=[message_json(row) for row in reversed(rows)];db.commit()
  health=await manager.client.health()
  return {'npc':'Bram','profile_id':p.id,'revision':revision,'messages':messages,'service':health,'error':ERRORS.get(health.get('error'))}
 @app.post('/api/npc/blacksmith/load',status_code=202)
 async def load(p=Depends(auth)):
  try:await manager.client.load()
  except RuntimeError:raise HTTPException(503,ERRORS['service_offline']) from None
  return {'message':'Loading the local model. You can keep playing.'}
 @app.post('/api/npc/blacksmith/messages',status_code=202)
 async def send(body:Message,p=Depends(auth),db=Depends(db_session)):
  text=body.text.strip()
  if not text:raise HTTPException(422,'Enter a message first.')
  conv=conversation(db,p)
  if conv.revision!=body.revision:raise HTTPException(409,'Conversation changed. Reload the dialogue before sending.')
  previous=db.scalar(select(NPCMessage).where(NPCMessage.player_id==p.id,NPCMessage.request_key==body.request_key))
  if previous:
   if previous.prompt!=text or previous.revision!=body.revision:raise HTTPException(409,'Request key already used for another message.')
   if previous.status!='failed':result=message_json(previous);db.commit();return result
  active=db.scalar(select(NPCMessage).where(NPCMessage.player_id==p.id,NPCMessage.status.in_(('queued','generating'))))
  if active:raise HTTPException(409,'The smith is still preparing your previous reply.')
  # Do not hold player/database locks while talking to the model process.
  facts=facts_for(db,p.id,body.campaign)
  prior=list(db.scalars(select(NPCMessage).where(NPCMessage.player_id==p.id,NPCMessage.revision==body.revision,NPCMessage.status=='completed').order_by(NPCMessage.created_at.desc()).limit(3)))
  context=[]
  for row in reversed(prior):context.extend([{'role':'user','content':row.prompt},{'role':'assistant','content':row.reply}])
  if previous:row=previous;row.status='queued';row.error_code=None
  else:row=NPCMessage(player_id=p.id,request_key=body.request_key,revision=body.revision,prompt=text,status='queued');db.add(row)
  db.flush();mid=row.id;response=message_json(row)
  # Bound stored history as well as model context. Clear removes every message for this profile.
  old=list(db.scalars(select(NPCMessage.id).where(NPCMessage.player_id==p.id).order_by(NPCMessage.created_at.desc()).offset(12)))
  if old:db.execute(delete(NPCMessage).where(NPCMessage.id.in_(old)))
  db.commit()
  manager.launch(mid,{'request_id':mid,'facts':facts,'history':context,'message':text})
  return response
 @app.delete('/api/npc/blacksmith')
 async def clear(body:Clear,p=Depends(auth),db=Depends(db_session)):
  conv=conversation(db,p)
  if conv.revision!=body.revision:raise HTTPException(409,'Conversation already changed. Refresh the dialogue.')
  ids=list(db.scalars(select(NPCMessage.id).where(NPCMessage.player_id==p.id)))
  db.execute(delete(NPCMessage).where(NPCMessage.player_id==p.id));conv.revision+=1;revision=conv.revision;db.commit()
  for mid in ids:
   if mid in manager.tasks:manager.tasks[mid].cancel()
  return {'revision':revision,'message':'Conversation cleared.'}
