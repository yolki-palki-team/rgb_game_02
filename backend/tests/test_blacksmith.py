"""Isolated API tests. Stubbed inference here; real QVAC is tested by check_blacksmith.py."""
import asyncio,time,uuid,json
from sqlalchemy import select,func
from sqlalchemy.orm import Session
from backend.tests.test_api import api,win
from backend.app.models import NPCMessage,NPCConversation,ItemInstance,ItemOperation,Player,LootReward,RGBAsset
from backend.app.services.blacksmith import MODEL,Blacksmith

class InferenceFixture:
 def __init__(self,delay=0):self.payloads=[];self.delay=delay;self.error=None
 async def health(self):return {'state':'ready','model':MODEL,'provider':'qvac','local':True}
 async def load(self):pass
 async def reply(self,payload):
  self.payloads.append(payload);await asyncio.sleep(self.delay)
  if self.error:raise RuntimeError(self.error)
  return {'reply':'Unit test reply, not model evidence.','model':MODEL,'duration_ms':1}

def setup(api,delay=0):
 fixture=InferenceFixture(delay);api.app.state.blacksmith.client=fixture
 return fixture

def request(text='What is my weapon?',revision=0,key=None):return {'text':text,'request_key':key or uuid.uuid4().hex,'revision':revision}
def wait(api,headers=None):
 for _ in range(100):
  data=api.get('/api/npc/blacksmith',headers=headers).json()
  if data['messages'] and data['messages'][-1]['status'] in ('completed','failed'):return data
  time.sleep(.01)
 raise AssertionError('No terminal reply')

def test_blacksmith_auth_context_and_readonly(api):
 fixture=setup(api)
 assert api.get('/api/npc/blacksmith',headers={'Authorization':'Bearer wrong'}).status_code==401
 other=api.post('/api/players',json={'name':'Other secret profile'}).json()
 win(api) # A server-earned pending instance must be explained as unavailable, never owned by assertion.
 campaign={'health':70,'stamina':55,'gold':12,'potions':2,'inventory':['iron','armor'],'weapon':'iron','armor':'armor'}
 before=api.get('/api/relics').json()['items']
 body={**request(), 'campaign':campaign}
 assert api.post('/api/npc/blacksmith/messages',json={**body,'asset_id':'stolen'}).status_code==422
 assert api.post('/api/npc/blacksmith/messages',json={**body,'player_id':other['id']}).status_code==422
 assert api.post('/api/npc/blacksmith/messages',json={**body,'campaign':{**campaign,'weapon':'injected'}}).status_code==422
 assert api.post('/api/npc/blacksmith/messages',json=body).status_code==202
 assert wait(api)['messages'][-1]['status']=='completed'
 payload=fixture.payloads[0];encoded=json.dumps(payload)
 for forbidden in ('token','mnemonic','seed','fingerprint','invoice','asset_id',other['id'],other['name'],api.player_id):assert forbidden not in encoded
 assert payload['facts']['campaign']['effective_damage']==22
 assert payload['facts']['rgb_items'][0]['can_equip'] is False
 assert before==api.get('/api/relics').json()['items']
 with Session(api.app.state.engine) as db:assert db.scalar(select(func.count()).select_from(RGBAsset))==0

def test_blacksmith_profiles_idempotency_and_history_limit(api):
 fixture=setup(api,.03);body=request();first=api.post('/api/npc/blacksmith/messages',json=body).json()
 assert api.post('/api/npc/blacksmith/messages',json=body).json()['id']==first['id']
 assert api.post('/api/npc/blacksmith/messages',json=request()).status_code==409
 wait(api)
 assert len(fixture.payloads)==1
 assert api.post('/api/npc/blacksmith/messages',json={**body,'text':'different'}).status_code==409
 other=api.post('/api/players',json={'name':'Other'}).json();headers={'Authorization':'Bearer '+other['token']}
 assert api.get('/api/npc/blacksmith',headers=headers).json()['messages']==[]
 assert api.post('/api/npc/blacksmith/messages',headers=headers,json=body).status_code==202
 wait(api,headers);assert fixture.payloads[-1]['history']==[]
 for _ in range(13):
  assert api.post('/api/npc/blacksmith/messages',json=request()).status_code==202
  wait(api)
 assert len(api.get('/api/npc/blacksmith').json()['messages'])==12
 assert len(fixture.payloads[-1]['history'])==6
 assert len(api.get('/api/npc/blacksmith',headers=headers).json()['messages'])==1

def test_blacksmith_clear_cancels_and_revision_fences_late_messages(api):
 fixture=setup(api,.2);body=request()
 api.post('/api/npc/blacksmith/messages',json=body)
 cleared=api.request('DELETE','/api/npc/blacksmith',json={'revision':0});assert cleared.json()['revision']==1
 time.sleep(.25)
 assert api.get('/api/npc/blacksmith').json()['messages']==[]
 assert api.post('/api/npc/blacksmith/messages',json=body).status_code==409
 assert api.post('/api/npc/blacksmith/messages',json=request(revision=1)).status_code==202
 assert wait(api)['messages'][-1]['status']=='completed'
 assert fixture.payloads[-1]['history']==[]

def test_blacksmith_offline_timeout_retry_and_restart(api):
 fixture=setup(api);fixture.error='service_offline';body=request()
 mid=api.post('/api/npc/blacksmith/messages',json=body).json()['id']
 assert wait(api)['messages'][-1]['error_code']=='service_offline'
 fixture.error='inference_timeout'
 assert api.post('/api/npc/blacksmith/messages',json=body).json()['id']==mid
 assert wait(api)['messages'][-1]['error_code']=='inference_timeout'
 fixture.error=None
 api.post('/api/npc/blacksmith/messages',json=body)
 assert wait(api)['messages'][-1]['status']=='completed'
 with Session(api.app.state.engine) as db:
  row=NPCMessage(player_id=api.player_id,request_key=uuid.uuid4().hex,revision=0,prompt='Interrupted',status='generating');db.add(row);db.commit();mid=row.id
 api.app.state.blacksmith.recover()
 with Session(api.app.state.engine) as db:
  row=db.get(NPCMessage,mid);assert row.status=='failed';assert row.error_code=='server_restarted'
