"""Gameplay metadata and custodial RGB evidence are deliberately separate tables."""
from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import String, Integer, Boolean, Float, DateTime, ForeignKey, JSON, UniqueConstraint, false
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

def uid(): return str(uuid4())
def now(): return datetime.now(timezone.utc)
class Base(DeclarativeBase): pass
class Player(Base):
 __tablename__='players'
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 name: Mapped[str]=mapped_column(String(32))
 is_test: Mapped[bool]=mapped_column(Boolean,default=False,server_default=false(),index=True)
 token_hash: Mapped[str]=mapped_column(String(64),unique=True)
 created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)
class GameSession(Base):
 __tablename__='game_sessions'
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'),index=True)
 state: Mapped[dict]=mapped_column(JSON)
 last_action: Mapped[float]=mapped_column(Float,default=0)
 created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)
class Item(Base):
 __tablename__='items'
 id: Mapped[str]=mapped_column(String(64),primary_key=True)
 name: Mapped[str]=mapped_column(String(80))
 rarity: Mapped[str]=mapped_column(String(20))
 slot: Mapped[str]=mapped_column(String(20))
 damage: Mapped[int]=mapped_column(Integer,default=0)
 description: Mapped[str]=mapped_column(String(512),default='')
class InventoryEntry(Base):
 __tablename__='inventory_entries'
 __table_args__=(UniqueConstraint('player_id','item_id','source_session'),)
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'),index=True)
 item_id: Mapped[str]=mapped_column(ForeignKey('items.id'))
 source_session: Mapped[str]=mapped_column(String(36),default='starter')
 quantity: Mapped[int]=mapped_column(Integer,default=1)
 rgb_asset_id: Mapped[str|None]=mapped_column(String(200),nullable=True)
class Equipment(Base):
 __tablename__='equipment'
 __table_args__=(UniqueConstraint('player_id','slot'),)
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'))
 slot: Mapped[str]=mapped_column(String(20))
 inventory_id: Mapped[str]=mapped_column(ForeignKey('inventory_entries.id'))
class LootReward(Base):
 __tablename__='loot_rewards'
 __table_args__=(UniqueConstraint('player_id','idempotency_key'),UniqueConstraint('session_id'))
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'))
 session_id: Mapped[str]=mapped_column(ForeignKey('game_sessions.id'))
 idempotency_key: Mapped[str]=mapped_column(String(128))
 inventory_id: Mapped[str]=mapped_column(ForeignKey('inventory_entries.id'))
class CommandReceipt(Base):
 __tablename__='command_receipts'
 __table_args__=(UniqueConstraint('session_id','key'),UniqueConstraint('session_id','turn'),)
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 session_id: Mapped[str]=mapped_column(ForeignKey('game_sessions.id'))
 key: Mapped[str]=mapped_column(String(128))
 turn: Mapped[int]=mapped_column(Integer)
 action: Mapped[str]=mapped_column(String(20))
 result: Mapped[dict]=mapped_column(JSON)
class RGBAsset(Base):
 __tablename__='rgb_assets'
 asset_id: Mapped[str]=mapped_column(String(200),primary_key=True)
 category: Mapped[str]=mapped_column(String(8))
 item_id: Mapped[str|None]=mapped_column(ForeignKey('items.id'),nullable=True)
 player_id: Mapped[str|None]=mapped_column(ForeignKey('players.id'),nullable=True)
 mode: Mapped[str]=mapped_column(String(10))
 ownership: Mapped[str]=mapped_column(String(32),default='pending_verification')
 metadata_json: Mapped[dict]=mapped_column(JSON,default=dict)
class RGBTransfer(Base):
 __tablename__='rgb_transfers'
 __table_args__=(UniqueConstraint('player_id','idempotency_key'),)
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'))
 asset_id: Mapped[str]=mapped_column(ForeignKey('rgb_assets.asset_id'))
 idempotency_key: Mapped[str]=mapped_column(String(128))
 recipient: Mapped[str]=mapped_column(String(2048))
 state: Mapped[str]=mapped_column(String(40),default='requested')
 mode: Mapped[str]=mapped_column(String(10))
 txid: Mapped[str|None]=mapped_column(String(64),nullable=True)
 batch_idx: Mapped[int|None]=mapped_column(Integer,nullable=True)
 error_code: Mapped[str|None]=mapped_column(String(80),nullable=True)
 created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)

class ManagedWallet(Base):
 __tablename__='managed_wallets'
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'),primary_key=True)
 status: Mapped[str]=mapped_column(String(32),default='preparing')
 # Public fingerprint only; mnemonic never enters the application DB.
 fingerprint: Mapped[str|None]=mapped_column(String(16),nullable=True)

class ItemInstance(Base):
 __tablename__='item_instances'
 serial: Mapped[int]=mapped_column(Integer,primary_key=True,autoincrement=True)
 type_id: Mapped[str]=mapped_column(ForeignKey('items.id'))
 reward_id: Mapped[str]=mapped_column(ForeignKey('loot_rewards.id'),unique=True)
 beneficiary_id: Mapped[str]=mapped_column(ForeignKey('players.id'))
 owner_id: Mapped[str|None]=mapped_column(ForeignKey('players.id'),nullable=True,index=True)
 asset_id: Mapped[str|None]=mapped_column(ForeignKey('rgb_assets.asset_id'),unique=True,nullable=True)
 state: Mapped[str]=mapped_column(String(32),default='earned')
 verified_at: Mapped[float]=mapped_column(Float,default=0)
 # Maximum previously granted client use lease; recipient cannot activate before this expires.
 use_until: Mapped[float]=mapped_column(Float,default=0)
 revision: Mapped[int]=mapped_column(Integer,default=0)

class RelicEquipment(Base):
 __tablename__='relic_equipment'
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'),primary_key=True)
 serial: Mapped[int]=mapped_column(ForeignKey('item_instances.serial'),unique=True)

class ItemOperation(Base):
 __tablename__='item_operations'
 __table_args__=(UniqueConstraint('requester_id','request_key'),)
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 serial: Mapped[int]=mapped_column(ForeignKey('item_instances.serial'),index=True)
 kind: Mapped[str]=mapped_column(String(16)) # award or transfer
 requester_id: Mapped[str]=mapped_column(ForeignKey('players.id'))
 recipient_id: Mapped[str]=mapped_column(ForeignKey('players.id'))
 sender_id: Mapped[str|None]=mapped_column(ForeignKey('players.id'),nullable=True) # None = issuer
 request_key: Mapped[str]=mapped_column(String(128))
 state: Mapped[str]=mapped_column(String(40),default='earned')
 invoice: Mapped[str|None]=mapped_column(String(4096),nullable=True)
 batch_idx: Mapped[int|None]=mapped_column(Integer,nullable=True)
 txid: Mapped[str|None]=mapped_column(String(64),nullable=True)
 error_code: Mapped[str|None]=mapped_column(String(80),nullable=True)
 created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)

class ItemEvent(Base):
 __tablename__='item_events'
 id: Mapped[int]=mapped_column(Integer,primary_key=True,autoincrement=True)
 operation_id: Mapped[str]=mapped_column(ForeignKey('item_operations.id'),index=True)
 state: Mapped[str]=mapped_column(String(40))
 created_at: Mapped[datetime]=mapped_column(DateTime(timezone=True),default=now)

class WorkerState(Base):
 __tablename__='worker_state'
 id: Mapped[str]=mapped_column(String(24),primary_key=True)
 heartbeat: Mapped[float]=mapped_column(Float,default=0)
 available: Mapped[int]=mapped_column(Integer,default=0)
 error_code: Mapped[str|None]=mapped_column(String(80),nullable=True)
 block_height: Mapped[int|None]=mapped_column(Integer,nullable=True)

class NPCConversation(Base):
 __tablename__='npc_conversations'
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'),primary_key=True)
 revision: Mapped[int]=mapped_column(Integer,default=0)

class NPCMessage(Base):
 __tablename__='npc_messages'
 __table_args__=(UniqueConstraint('player_id','request_key'),)
 id: Mapped[str]=mapped_column(String(36),primary_key=True,default=uid)
 player_id: Mapped[str]=mapped_column(ForeignKey('players.id'),index=True)
 request_key: Mapped[str]=mapped_column(String(64))
 revision: Mapped[int]=mapped_column(Integer)
 prompt: Mapped[str]=mapped_column(String(600))
 reply: Mapped[str|None]=mapped_column(String(600),nullable=True)
 status: Mapped[str]=mapped_column(String(20),default='queued')
 error_code: Mapped[str|None]=mapped_column(String(40),nullable=True)
 model: Mapped[str|None]=mapped_column(String(80),nullable=True)
 duration_ms: Mapped[int|None]=mapped_column(Integer,nullable=True)
 created_at: Mapped[float]=mapped_column(Float,default=lambda:datetime.now(timezone.utc).timestamp())
