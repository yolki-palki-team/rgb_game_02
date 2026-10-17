import os
from pathlib import Path
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from .models import Base, Item

CATALOG=[
 dict(id='warden_iron',name="Warden's Iron",rarity='Common',slot='weapon',damage=22,description='Cloud starter blade.'),
 dict(id='oath_relic',name='Flame Sword',rarity='Legendary',slot='weapon',damage=52,description='A reward from the Keeper. Unique RGB sword: 52 damage. Transferable between players.'),
]
def make_engine(url=None):
 url=url or os.getenv('DATABASE_URL','sqlite:///.state/runeforge.db')
 if url.startswith('sqlite:'):Path('.state').mkdir(exist_ok=True)
 engine=create_engine(url,connect_args={'check_same_thread':False,'timeout':30} if url.startswith('sqlite:') else {},pool_pre_ping=True)
 if url.startswith('sqlite:'):
  @event.listens_for(engine,'connect')
  def pragma(dbapi,_):dbapi.execute('PRAGMA foreign_keys=ON');dbapi.execute('PRAGMA journal_mode=WAL')
 return engine

def seed(engine):
 with sessionmaker(engine)() as db,db.begin():
  for item in CATALOG:
   if db.get(Item,item['id']) is None:db.add(Item(**item))
   elif item['id']=='oath_relic':
    row=db.get(Item,item['id'])
    for key,value in item.items():setattr(row,key,value)
