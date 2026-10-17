"""Profile-scoped, read-only blacksmith conversations. No wallet schema changes."""
from alembic import op
from backend.app.models import NPCConversation,NPCMessage
revision='0004'
down_revision='0003'
branch_labels=None
depends_on=None
def upgrade():
 NPCConversation.__table__.create(op.get_bind(),checkfirst=True)
 NPCMessage.__table__.create(op.get_bind(),checkfirst=True)
def downgrade():
 NPCMessage.__table__.drop(op.get_bind(),checkfirst=True)
 NPCConversation.__table__.drop(op.get_bind(),checkfirst=True)
