# Verification record — managed player items

Environment: macOS arm64, Godot 4.4.1 OpenGL Compatibility, Python 3.14, PostgreSQL 17, Docker Desktop, official rgb-lib **0.3.0b7**. Only isolated RuneForge regtest funds/wallets were used.

## Automated checks passed

- **21 backend tests** on SQLite and **21 on PostgreSQL**. PostgreSQL tests create and remove their own unique schemas; they do not clear gameplay tables. Includes strict input/auth, forged victory rejection, command replay, concurrent reward claims, automatic instance creation, registration replay, foreign asset refusal, expired evidence, atomic competing transfers, lease preservation, and waiting for recipient settlement before granting access.
- Existing campaign headless smoke: map connectivity, movement, collision, keeper, chest idempotency, shrine, player/enemy damage, melee/projectiles, dodge, boss phase and loot, equipment, save/load, corrupt-save rejection, death/respawn. Expanded with verified weapon override and lease expiry.
- Editor import / GDScript parse checks: passed.
- Pinned SDK signature check: passed, including mandatory expiration_timestamp and actual OnlineOptions interface.
- Existing two policy tests remain unchanged; no ML work added.

`./scripts/check.sh` runs the local suite. The Starlette TestClient/httpx deprecation warning is upstream and non-failing; dependencies were not migrated for this change.

## Real regtest integration

`scripts/managed_e2e.py` passed from a fresh pair of profiles and different RGB wallet fingerprints:

1. Server-judged victory and one durable reward/instance.
2. UDA native issuance followed by process exit before journal completion; recovery finds exactly one contract.
3. Actual issuer→A transfer, both SDKs settled, A verified equipment damage 52.
4. A→B reservation, unequip, replay returning same operation, competing/foreign requests rejected.
5. Native send followed by exit before saving its result; restart recovers actual SDK batch/txid.
6. Same instance and asset_id at B, sender settled=0, receiver settled/spendable=1; A denied, B equipped.
7. Recovery after a live worker SIGKILL left a native SDK runtime marker; exclusive adapter lock permits archiving only the stale marker, never wallet state.

Public IDs, transaction IDs, observed stages and checks: [managed-e2e.json](evidence/managed-e2e.json). Later test reruns reuse this instance and exercise persistence/idempotency rather than minting another reward. Crash checkpoints belong to the first successful fresh run.

`--managed-game-check` passed through the real Godot HTTP client with its own separate test profiles and a separately earned UDA. It won the trial, equipped A, called actual campaign `attack()` and measured exactly 52 damage, requested the real transfer, observed removal of sender stats, switched to B and equipped the same item. [managed-godot.json](evidence/managed-godot.json).

## Outages and launch

`check_outages.py` really stopped electrs, proxy and the API, then restored them:

- electrs/proxy offline: equip and send return 503, no new use lease, existing selection becomes unavailable. Restart rechecks actual allocations and permits equip.
- API stopped after Godot equipped a real UDA: connection error displayed, lease expires, RGB damage becomes unavailable, ordinary 22-damage sword is restored.
- Services restored; public result in [outages.json](evidence/outages.json).
- `start.sh --no-game` repeated successfully, preserving process PIDs, database and wallet state. The full verification wrapper was also run after these changes.
- Managed mnemonic permissions checked (0600); exact managed seeds scanned against SDK/process logs with zero matches. Credentials and wallet state are excluded from published evidence.

## Visual evidence and manual-test limit

Actual Godot 1280×720 renderer output was inspected: [trial](evidence/trial.png), [sender](evidence/managed-sender.png), [recipient](evidence/managed-recipient.png), [backend offline](evidence/backend-offline.png). Existing hub/dungeon/boss/inventory assets are retained. Item image, serial, 52 damage, ownership, equipment and transfer controls are visible.

**Manual interaction through Computer Use did not pass and is not claimed.** The tool returned `Computer Use was not approved to use Godot`. The GUI was rendered and automated client behavior was tested, but real pointer/keyboard interaction with the new panels could not be independently exercised through that tool.

Still untested/unsupported: deep Bitcoin reorganizations, disk corruption and machine-loss recovery; external wallets/deposits, trading, remote production security, controller/accessibility and a broad manual playtest. Ambiguous native outcomes stay reserved rather than inventing success or unlocking ownership.

## Sword #4 correction

The accidental test recipient was repaired by a **new real RGB transfer** of the original UDA, with no new issuance. `sword4-return.json` records original asset ID, return txid, distinct wallet fingerprints, bilateral native settlement, sender=0, ordinary A=1 and exactly one issued contract for instance 4. The Godot check loaded the actual ordinary profile file and equipped #4 as ordinary A; `sword4-godot.json` and `sword4-ordinary-A.png` show this identity, 52 damage, ordinary B as the sole recipient, and the completed operation message. No new trial was started.

The suite now has **23 backend tests**, passing on SQLite and PostgreSQL. Added regression coverage for name-independent test-account isolation, rejection of cross-purpose transfer requests, and immutable account purpose on registration replay. Existing campaigns and save files were preserved. Running Godot windows need a normal save-and-restart to load the changed client scripts; backend filtering is already live.

## Native local blacksmith — 2026-10-17

29 backend tests passed on SQLite and PostgreSQL, including isolated dialogue fixtures for auth, bounded history, profile isolation, idempotency, clear/cancellation, retries and restart recovery. The Node output-validator check passed. Godot import and ordinary campaign smoke passed.

Separate **real inference** checks passed against QVAC SDK 0.21.1 / Qwen3 4B Q4_K_M: [API, actual service outage and isolated API crash recovery](evidence/blacksmith-api.json), [Godot input → API → model](evidence/blacksmith-godot.json), and [initial download progress](evidence/blacksmith-download.json). Existing item/owner/asset/operation state was compared before and after read-only model tests and remained unchanged. Full instructions and distinctions between fixture tests and real inference are in [BLACKSMITH.md](BLACKSMITH.md).

The dialogue was **not manually clicked or visually verified** with Computer Use. Headless geometry and input checks passed; denied Godot access remains the manual-check limitation. Generation timeouts are covered by isolated error-path tests; the real model completed normal test replies in roughly 1.5–2.5 seconds on the tested Mac. No real timeout duration claim is made.
