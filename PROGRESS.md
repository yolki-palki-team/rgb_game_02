# RuneForge build journal

Milestones are marked verified only after relevant checks run. Real chain evidence is separate from mock tests.

## M1 — Inspection (verified)
- Inspected the empty game workspace, existing Python virtual environment, sibling hackathon README, materials, settlement report and pinned native manifest. No existing user implementation or assets modified.
- Verified installed `rgb-lib==0.3.0b7` by package metadata and introspected actual Python signatures. `OnlineOptions` is required; `expiration_timestamp` is mandatory for receive/send.
- Official pinned source: RGB-Tools/rgb-lib `1eaf0024c591e41843eb80cc8834082292668871`; core RGB 0.11.1-rc.11. No RGB-WG dependencies.
- Godot missing. Downloading official 4.4.1 and backend dependencies into this workspace.
- Check: file inventory, clean Git status, Python package/version/signature inspection succeeded.

## Implementation decisions
- Original procedural pixel art; no third-party game art or remote generation dependency.
- Offline campaign stays playable without servers. Local campaign saves are untrusted and never authorize RGB rewards.
- A separate server-authoritative Oath Trial validates action sequences and awards cloud inventory transactionally. RGB ownership is independent of gameplay metadata.

## M2–M4 — Playable campaign (implemented; runtime QA underway)
- Created 33 original assets: four-frame characters, village props, tiled crypt, rarity icons, lighting and six synthesized effects.
- Implemented collision with substeps, sword aiming, stamina, invulnerable dodge, potions, damage, death and shrine respawn.
- Skeleton/goblin/mage FSMs, ranged bolts, telegraphs, boss sweep/nova/fan attacks and adaptive second phase.
- Hub keeper quest, three treasure chests, seven mobs, boss relic, equipment, atomic local save/load, title/settings/pause/inventory/vault UI.
- Check: official Godot 4.4.1 imported all assets and scripts without parse errors. Runtime smoke is next; not yet claiming gameplay validation.

## M2–M4 — Verified
- Godot runtime smoke passed movement, collision/roll tunneling, combat damage, dodge, boss phase II, boss loot, equipment, save/load, death and respawn.
- Captured and visually inspected `docs/evidence/crypt.png` from the actual Godot renderer. World, actors, art, lights and HUD render correctly at 1280×720.
- Found a harmless JSON parse log when the API is offline; correcting the network failure path during integration.

## M5 — Backend (SQLite verified, PostgreSQL verification underway)
- FastAPI bearer-authenticated player/inventory/equipment/session/combat/reward/ownership/vault APIs.
- SQLAlchemy schema plus Alembic migration; PostgreSQL 17 Compose service and SQLite offline development fallback.
- Server-owned Oath Trial uses validated command sequences, turn/cooldown checks, row locks and unique reward/command keys. No client victory or local save can mint a reward.
- Eight SQLite tests passed, including concurrent reward replay, cross-player isolation and pending RGB ownership rejection.
- PostgreSQL migration applied successfully. Running the same tests against PostgreSQL.

## M6–M8 — Integration underway
- Game connects to FastAPI, persists a bearer profile token, plays the authoritative trial, and claims cloud rewards. Local campaign loot is visibly separate.
- Official pinned source examples reviewed before implementation. Exact installed Python signatures saved in `docs/evidence/rgb-signatures.json`.
- Note: pinned Rust source exposes newer `list_transfers(AssetFilter, txid)` while the installed beta.7 Python wheel exposes `list_transfers(asset_id)`. The adapter uses and tests the actual pinned Python signature.
- Real regtest-only wallet adapter, independent issuer/receiver profiles, issuance, receive/send/refresh/balances, exclusive wallet locks and durable intent journal implemented.
- Isolated Bitcoin Core 30.2, electrs 0.11.0, RGB proxy 0.3.0 running. Newly generated keys remain in ignored `.state/` with restricted permissions. No sibling wallet state touched.

## M5–M6 — Verified
- The same eight API tests passed against PostgreSQL, including concurrent reward claims.
- Godot HTTP integration smoke passed authenticated registration, server trial victory, durable PostgreSQL reward, and replay returning only one reward.
- Fixed offline-response JSON parsing and isolated headless campaign test saves from normal save files.

## M7–M8 — Real regtest verified
- `scripts/regtest_demo.py` passed with real issuer and receiver wallets: fixed-supply 1,000,000-unit NIA issuance, 25-unit transfer, unique UDA issuance with PNG metadata, and UDA transfer.
- Sender/receiver SDK balances reconciled and receiver transfers reached SETTLED. Same-key send replay returned identical txids.
- Evidence: `docs/evidence/rgb-regtest.json`. These are local Bitcoin regtest transactions, not mocks or public-chain transactions.
- Fixed two observed SDK behaviors using official tests: repeat UTXO preparation raises AllocationsAlreadyAvailable; first-time UDA receive uses Assignment.ANY, then the sender supplies NON_FUNGIBLE.
- Operator bridge from a server-validated inventory reward to real UDA issuance and authenticated withdrawal implemented; end-to-end economic mapping check next.

## M9 — Adaptive AI implemented
- Rule-based boss tracks attacks/dodges, distance samples, damage taken, and duration; favors delayed nova against frequent dodges, bolt fan at range, and accelerates phase II.
- A small Python policy mirror enables deterministic checks. No neural training claim; Gymnasium/PyTorch work deferred.

## M8 — Economic bridge verified
- `scripts/economy_demo.py` passed server victory → durable reward → idempotent real UDA issuance → verified custodial equipment → authenticated reservation/unequip → actual receiver settlement → withdrawn ownership.
- Recorded separate public proof in `docs/evidence/economy-regtest.json`. No bearer tokens or keys exported.

## M9 — Verified
- Python tests passed adaptive distance/dodge policy and telemetry metrics. Godot smoke passed phase transition and actual melee/ranged attack execution.

## M10 — Final QA and delivery
- Expanded campaign smoke passed map connectivity to all chests and boss, keeper quest, one-time chest loot, shrine restoration, enemy melee and mage projectiles, all prior combat/save checks, and input focus protecting invoice typing.
- Added inventory tooltips/equipment slots, persistent settings, architectural props, banners, rubble, vegetation, woven arena runner and updated screenshots. Visually inspected title, hub, crypt, boss, inventory and Vault at 1280×720; no missing textures or clipped UI.
- Final Python suite: 18 tests passed. Includes new interrupted-send reconciliation, expiry-safe replay, and unknown-outcome reservation tests. PostgreSQL API suite passed separately.
- Docker backend image built successfully; Compose configuration and persistence paths verified.
- README, launch scripts, architecture, RGB operator/receiver/recovery runbook, asset licenses and QA scope written. Optional neural training, external-wallet ownership proofs and production deployment hardening remain explicitly deferred.
- Final expanded Godot smoke passed after corrupt-save validation; final live Godot→FastAPI→PostgreSQL smoke passed again with an isolated test profile.
- Built-container API tests also passed against PostgreSQL: 8/8. Host Python suite: 18/18. `git diff --check` passed.
- Delivery game launched successfully in the native Godot window. Native UI automation could observe the title but could not consistently bind input across Godot processes; no claim of an exhaustive manual campaign playthrough is made. Scripted gameplay and actual renderer checks are the recorded evidence.

## Managed player-item scenario — 2026-10-17

This revision supersedes the older mock-default/manual-operator delivery described above.

- Inspected actual backend, Godot, operator code, local RGB docs/resources, pinned official source and installed Python binding. Retained Godot 4.4.1 and rgb-lib 0.3.0b7; no RGB-WG/v0.12 migration.
- Added catalog/instance/contract separation, managed wallet mapping, durable operations/events, per-instance equipment, worker health and Alembic 0002. Applied migration without resetting data.
- Server victory now atomically earns one reward and queues automatic real UDA delivery. Worker manages isolated issuer and separate player wallets, funding, invoices, native sends, confirmations and bilateral ownership reconciliation.
- Transfers reserve/unequip before native calls. Same serial/asset moves A→B only after both wallets settle and old use leases expire. Legacy raw ownership claims cannot equip; external withdrawal/invoice routes retired.
- Fixed real integration defects found during testing: RPC bool serialization; incomplete receiver transfer lookup; premature terminal sender-only settlement; native stale runtime marker after SIGKILL. Added targeted settlement/lease regression test.
- Real fresh two-wallet test passed native issue/send crash recovery, one issuance, delivery, equip, transfer, duplicate/forged requests, same asset and sender revocation. Public proof: docs/evidence/managed-e2e.json.
- Godot now has visible village trial portal, illustrated duel/reward screen, item cards, actual 52-damage campaign equipment, profile selection, transfer confirmation, real status/history and technical disclosure. Original campaign and save format preserved.
- Real Godot scenario passed victory→receive→equip→actual 52-damage attack→transfer→recipient equip. Captured actual sender/recipient renderer evidence.
- Real electrs/proxy/API outages and recovery passed; disconnected Godot revokes leased RGB stats and restores ordinary weapon.
- 21 backend tests passed on SQLite and PostgreSQL; SDK interface verification and Godot parse/smoke passed. Existing policy tests unchanged.
- Added persistent one-command launcher and repeatable full integration wrapper; repeated startup preserves state/processes. Updated README, RGB, architecture and QA docs.
- Manual UI test is blocked by Computer Use refusing Godot access. Rendered images were inspected; manual clicks are not reported as passed.
- Limits: service-managed keys, local regtest only; no external deposit/ownership, barter or atomic exchange. Ambiguous or corrupted native state remains reserved for operator investigation.
- Repeated electrs interruption exposed cached SDK reconnect latency beyond the original 45-second test deadline. Worker now discards SDK connections after infrastructure/verification failures; recovery checks allow the real service up to 120 seconds while equipment remains unavailable.
- Final rerun passed actual electrs/proxy/backend outage recovery after connection reset, final Godot smoke, and idempotent real transfer verification with distinct public wallet fingerprints and matching_issuances=1. Transfer confirmation and corrected disconnected-item cards were rendered and visually inspected.

## Sword #4 recipient repair — 2026-10-17

- Confirmed the ordinary profile selector A resolves to `e2bc20f0-4fc2-49f4-8363-799560e64378`, whereas the accidental recipient Test A was `fbb6f7f7-31dc-4275-ba03-856ea737add6`.
- Returned the existing sword #4 through authenticated transfer intent + the real worker, not direct owner edits. Both native SDK wallets report SETTLED for txid `0e3158ba611f278d70ca79057b1a933846d1a2bed1cd36dc0ac6169d89192f55`. Source settled=0, ordinary A settled/spendable=1, original asset `rgb:HMuDmE2i-aknsETo-4mmIZrS-hrK12HK-Qn_Yi1F-kY5jYa8` unchanged, matching issuer contracts=1.
- Alembic 0003 adds explicit test-profile purpose. Classified the six existing automation profiles using their saved authenticated IDs, without guessing from names or changing ownership. New automated clients mark registration as test. Lists and new transfers are isolated by purpose on the server.
- Client selection retains recipient UUID rather than a changing list index; profile tabs use actual profile names and the active profile ID is visible. Transfer feedback now follows the recorded operation status and becomes “Передача завершена”; switching profiles clears stale feedback.
- 23 backend tests passed on SQLite and PostgreSQL, including hidden test recipients, server rejection of a crafted cross-purpose transfer and purpose-safe registration replay. Godot import/campaign smoke passed.
- Actual Godot `--verify-sword4` passed using ordinary `managed_profiles.json` (not test profiles): ordinary A identity, same asset, 52 damage, only ordinary B in recipient choices, completed transfer message after polling, and clearing messages on profile switch. Evidence: `docs/evidence/sword4-return.json`, `sword4-godot.json`, `sword4-ordinary-A.png`.


## Browser branch feature/javascript — 2026-10-17

Implemented JavaScript / Canvas 2D, same-origin API proxy, separate JS A/B browser profiles, real managed-item workflow and one-command launcher. Existing native campaign and RGB backend preserved.

Validated: 23 backend tests; 6 proxy tests; real HTTP trial/UDA/equipment/A→B transfer/sender revocation/recipient equipment (see docs/evidence/web-api-javascript.json). 11 JavaScript unit tests pass.

Browser QA is partial, not complete: initial Chromium launch succeeded; full/manual browser verification was blocked by denied Computer Use access. Browser tests stopped, no workaround attempted. See docs/WEB.md for exact observations and remaining checks.


## English localization — 2026-10-17

Translated README, menus, HUD, trial, equipment, transfer history, errors, catalog descriptions and managed RGB API messages into English. Existing built-in profile names are localized for display only; registration credentials and profile IDs remain unchanged. Catalog seeding updates presentation text without reissuing assets or changing ownership. Custom player names and historical evidence retain their original contents.

Validation: 25 backend tests and native Godot headless smoke pass; the JavaScript branch passes 11 unit tests. Full browser/manual UI verification remains blocked by the earlier denied Computer Use access and is not claimed as passed.

Live integration: restarted the local backend/worker only after confirming no transfers were pending. Verified English item/status responses through both web proxies and compared every item instance, asset_id, owner and state before/after restart: unchanged. WebAssembly release export also passed.
