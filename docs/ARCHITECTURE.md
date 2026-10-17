# Architecture and trust boundaries

## Game

`main.gd` preserves the offline chapter: collision, combat, actors, quests, loot, boss and atomic campaign saves. `interface.gd` draws the existing dark fantasy UI, the Oath Trial and managed-item cards. `network.gd` owns asynchronous authenticated requests, two local profile identities, operation intents and short equipment leases. Wallet keys never enter Godot.

The campaign pauses under panels. Its ordinary inventory, gold and local legendary relic remain local. `weapon_damage()`, `weapon_name()` and `weapon_icon()` use verified server equipment only while its monotonic lease is valid. Actual melee damage calls `weapon_damage()`. Expiry restores the locally selected weapon. RGB rights are never loaded from campaign JSON. Two managed profiles share this computer's ordinary campaign; their server inventories and wallets are separate.

The visible village forge opens the same server-authoritative tactical duel available from the item screen. The server owns HP, stamina, turns and victory; the campaign cannot assert victory. Valid trial commands can be automated, so this is not anti-bot protection.

## API and PostgreSQL

`main.py` authenticates profile tokens, owns profiles/trials/ordinary inventory, and atomically creates earned rewards. `api/managed.py` exposes item cards, fresh eligibility, equipment leases and authenticated transfer intents. `services/rewards.py` creates one reward/instance/award operation per verified session. Neither HTTP layer opens a wallet or signs.

`items` is the catalog; `item_instances` is identity; `rgb_assets` is registered contract metadata. Ownership is a reconciled relationship between an instance, a player's separate wallet and observed SDK allocation. Item stats are explicit in the catalog. A client-supplied asset ID has no enrollment route.

PostgreSQL player and instance row locks serialize requests, equipment renewal and transfer reservation. Unique constraints protect reward/session, instance/reward, contract/instance, operation/request key, and selected instance equipment. A transfer reserves before signing and removes equipment in the same transaction. The receiver cannot equip until actual bilateral settlement and expiry of any sender use lease. SQLite is used for isolated unit tests; the player scenario uses PostgreSQL and Alembic.

## Worker and RGB

`services/worker.py` is the only automatic signing process. `rgb/service.py` wraps exactly rgb-lib 0.3.0b7. `rgb/infrastructure.py` checks isolated regtest, funds only RuneForge wallets, creates allocations and mines real confirmations. `scripts/start.py` orchestrates persistent local services, runs migrations and avoids duplicate processes.

There is one managed issuer and one independent wallet per profile UUID. Native wallet state and local intent journals live under `.state/managed-v2`, outside Git. SQL contains fingerprints, contract IDs, public transaction IDs and operation states, not mnemonic keys. The service is trusted as custodian; it does not claim independent self-custody.

Issue, receive and send each persist intent before native effects. Reconciliation bridges the non-atomic boundary between native SDK and game SQL. Native results lost at process death are recovered from exact contract details or matching actual SDK transfers. Ambiguous results remain reserved. Two-sided settlement, current allocation and recent infrastructure evidence are required; a DB ownership flag alone is insufficient.

The normal runtime never instantiates MockRGB. Legacy raw receive/withdraw routes return 410, and legacy manual mint rejects managed rewards. Historical diagnostic scripts remain available for their separate older wallet directories.

See [RGB.md](RGB.md) for signatures, lease timing, stale SDK lock recovery and recovery limits.

## Scope

One ordinary local chapter and a server-judged trial; managed player-to-player UDA transfer on local regtest. No independent-device account enrollment UI, external-wallet deposit/ownership proof, marketplace, barter, atomic swap, production auth or mainnet. Existing enemy AI was preserved; this work adds no ML features. Reorgs, damaged wallet state and full disaster recovery need further testing/hardening.

## Local blacksmith

The native dialogue uses its own HTTPRequest against authenticated `/api/npc/blacksmith` endpoints so wallet lease polling remains independent. FastAPI builds a small current-player fact snapshot, persists a profile-scoped turn and performs inference asynchronously through the loopback Node/QVAC sidecar. The sidecar loads pinned local Qwen3 4B weights and exposes only model status, load and reply; there are no game actions or wallet APIs in its model interface. Per-profile revisioned history is bounded, and shared model KV caching is disabled. See [BLACKSMITH.md](BLACKSMITH.md) for privacy boundaries, cancellation, restart semantics and reproducible real inference checks.
