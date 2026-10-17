# RGB v0.11.1 regtest runbook

## Exact stack and verified sources

- Python **rgb-lib==0.3.0b7**. Its core RGB dependencies are **0.11.1-rc.11**.
- Official source revision inspected: [`1eaf0024c591e41843eb80cc8834082292668871`](https://github.com/RGB-Tools/rgb-lib/tree/1eaf0024c591e41843eb80cc8834082292668871).
- [Official C binding example](https://github.com/RGB-Tools/rgb-lib/blob/1eaf0024c591e41843eb80cc8834082292668871/bindings/c-ffi/example.c): wallet keys, online options, funding, allocations, issuance and receive flow.
- [Official UniFFI definitions](https://github.com/RGB-Tools/rgb-lib/blob/1eaf0024c591e41843eb80cc8834082292668871/bindings/uniffi/src/rgb-lib.udl): binding types and operations.
- [Official receive tests](https://github.com/RGB-Tools/rgb-lib/blob/1eaf0024c591e41843eb80cc8834082292668871/src/wallet/test/blind_receive.rs) and [send tests](https://github.com/RGB-Tools/rgb-lib/blob/1eaf0024c591e41843eb80cc8834082292668871/src/wallet/test/send.rs): unknown-contract invoice behavior and UDA round trips.
- [Official protocol documentation](https://docs.rgb.info/) and [RGB Protocol Association](https://rgb.info/).
- Bitcoin Core 30.2, electrs 0.11.0, RGB proxy 0.3.0. The Docker images match the official rgb-lib test Compose reference. Images are only development infrastructure; no third-party RGB stack is imported.

The installed wheel is the authority for Python signatures. The inspected Rust revision exposes `list_transfers(AssetFilter, txid)`, but **this exact Python wheel exposes `list_transfers(asset_id)`**. RuneForge checks and uses the actual wheel interface. Do not replace it with an API copied from current master or another stack.

```sh
.venv/bin/python scripts/verify_rgb_api.py
```

Saved signature evidence is in `evidence/rgb-signatures.json`. `OnlineOptions(indexer_url, skip_consistency_check=False, vanilla_sync_lookback=20)` is used. `blind_receive` and `send` receive an explicit absolute Unix `expiration_timestamp`; no invented default is assumed. Issuance methods in this release do not take an `Online` argument. `send` returns an `OperationResult`, not a bare txid.

## Implemented player flow (managed wallets, v2)

Run `./scripts/start.sh`. PostgreSQL :55432, Bitcoin RPC :18543, electrs :51001 and proxy :3100 belong to Compose project **runeforge**. FastAPI listens on loopback :8787. The host worker uses Docker's Bitcoin CLI only for this isolated regtest. It checks `getblockchaininfo.chain`, mines real regtest confirmations, waits for electrs and probes the proxy's actual `server.info` response. It never substitutes mock success.

**Custody:** one operator issuer plus one separate wallet per player UUID, all managed by the local service. The user trusts this service with keys and correct item registration. Wallet seed files are local, permission 0600, directories 0700, excluded from Git. They are not encrypted at rest. Game bearer credentials are separate from RGB signing keys. FastAPI never instantiates a signing wallet; only the worker does. Do not run another SDK process directly on these private wallet directories.

The instance model separates:

| Record | Meaning |
|---|---|
| `items.oath_relic` | Type: Flame Sword, Legendary, weapon, **52 damage** |
| `item_instances.serial` | One specific sword, stable across transfers |
| `item_instances.asset_id` | One genuine UDA issued for that exact earned instance |
| `item_operations` / `item_events` | Durable requested intent, observed stage, transaction and history |
| `managed_wallets` | Player-to-wallet association; only public fingerprint in SQL |
| `relic_equipment` | Current server-approved selection |
| `worker_state` | Fresh infrastructure heartbeat, never a fabricated chain status |

A verified server trial win creates the reward, instance and award operation **in the victory transaction**, before the client can claim anything. The worker issues under `managed-instance-<serial>` and embeds that unique key in actual contract details. Recovery checks the contract's metadata, not merely its name, artwork or short ticker. Only contracts registered by this path can become usable instances. Knowledge of an asset ID, an arbitrary signature, or a client-supplied victory cannot grant access.

Worker stages: earned → issuing → preparing invoice → signing → SDK WAITING_* states → settled. Both sender **and recipient** must report SETTLED; recipient settled/spendable must be 1 and sender settled must be 0. Only then does a DB transaction change the instance owner and move its inventory entry. The first delivery uses issuer → A; subsequent transfer uses **A's actual wallet → B's actual wallet**. Asset and serial remain unchanged.

`list_transfers(None)` does not replace querying a known asset's transfers in this binding. The receiver first refreshes open receives and then the registered asset; completion is based on both sides. A sender that has settled while a receiver has not remains `waiting_receiver`, not a terminal operation.

## Ownership and equipment

`GET /api/relics` returns only registered related instances, explicit type stats, current owner, history, available recipients and equipment. The worker refreshes actual wallet allocations continuously. An item is usable only while:

- its registered owner matches the authenticated player;
- state is `owned` and the wallet observation is less than **8 seconds** old;
- the worker/infrastructure heartbeat is less than **8 seconds** old and available;
- it is not reserved for transfer.

An equipped item gets a maximum **4-second** use lease, bounded by wallet evidence freshness. Godot uses a conservative monotonic deadline accounting for the request round trip. Expiry or connection error restores the ordinary campaign weapon. The server locks the instance for both lease renewal and reservation. Transfer immediately removes server equipment and stops new leases. Recipient access waits for the previous owner's last lease to expire as well as real settlement. This prevents simultaneous authorized use in two honest clients. A modified offline game can cheat its local campaign; it still cannot mint rewards or alter server ownership.

The legacy equipment endpoint refuses RGB rewards. Old external-withdrawal and manual-invoice HTTP endpoints return **410**. A stale `verified_custody` flag alone cannot authorize equipment. No external-wallet ownership claim or deposit facility is exposed.

## Player API

All item endpoints require the profile bearer token. `/api/players` accepts an optional random 256-bit `registration_key` for safe retry; the game persists it before registration. Tokens are hashed in SQL, and neither token nor key is a Bitcoin/RGB key.

- `POST /api/sessions`, `/api/sessions/{id}/commands`: authoritative tactical trial. Actions, turns, stamina, health, cooldown and idempotency are server checked.
- `POST /api/sessions/{id}/result`: return the already-earned reward; never trusts client victory.
- `GET /api/relics`: item screen, live eligibility, equipment lease, recipients, operation history.
- `POST /api/relics/{serial}/equip`: require fresh verified ownership.
- `DELETE /api/relics/equipment`: select ordinary equipment.
- `POST /api/relics/{serial}/transfer`: `{recipient_id, confirm: true, idempotency_key}`. Atomically reserve and unequip. Same intent/key returns the same operation. Concurrent distinct requests cannot transfer twice.

The client handles invoices automatically through the worker. There is no user-editable asset_id ownership field. Ordinary gold is local gameplay currency, not NIA. The older NIA library demo remains separate from this sword scenario.

## Persistence and recovery

Persist **all** of PostgreSQL volume, Bitcoin chain, electrs index, proxy consignments, `.state/managed-v2` wallet directories and Godot profile credentials. Re-running the launcher never deletes them. Each worker and wallet holds an OS advisory lock. Another worker cannot concurrently use the same managed root.

Per-wallet SQLite intent journals bind idempotency keys to exact issue/send/receive intent. Native issue can complete before the journal or game DB is updated: recovery finds the exact issued contract by full metadata key. Native send can complete before its receipt is stored: recovery matches the SDK transfer to the previously persisted invoice recipient and asset, then reuses its batch/txid. Issuance is never repeated merely because an HTTP request timed out. Receiver invoices also have a durable pre-operation transfer snapshot and recovery matching.

This SDK uses an empty `rgb_runtime.lock` created exclusively and removed on runtime drop. SIGKILL during refresh can leave it behind. After acquiring this adapter's exclusive OS wallet lock, startup archives that stale marker (does **not** remove stock, journal or wallet DB) before opening the SDK. This is safe only under the documented single-adapter ownership of these private directories. `go_online` retains `skip_consistency_check=False`; corruption must not be bypassed. Normal SIGTERM finishes the current worker tick and closes wallets.

If issuance/receive/send is ambiguous and cannot be matched uniquely, the operation stays reserved with `ambiguous_operation`. Do not generate a new key to force a retry. A failed transfer is released back to its sender only after SDK failure plus actual sender settled/spendable=1 and receiver settled/future=0. Outages never unlock a transfer. SDK connections are discarded after detected infrastructure/verification failures and reopened on recovery. An interrupted native call may take time to return; the stale heartbeat still prevents new use rights during that interval. Wallet balance divergence removes equipment and requires subsequent successful reconciliation.

For local diagnosis, stop only the launcher-owned worker, preserve a backup of the entire managed root and database, and inspect SDK transfer state with the existing adapter under its lock. Never edit ownership flags to pretend settlement. Hardware failure, damaged stock or unrecoverable ambiguous partial native operations require operator investigation; this MVP does not promise automatic repair of corrupted data.

## Reproduction and evidence

```sh
./scripts/start.sh
./scripts/check-managed.sh
```

The test driver first verifies a server victory, crashes the worker **after native UDA issuance before journal completion**, restarts, receives the single asset, equips A, rejects a forged asset claim, reserves a transfer, rejects a second transfer, crashes **after native send before journal completion**, then restarts and verifies B's real wallet and equipment. Separate fingerprints, issuer metadata, issuance count and both balances are checked. Reruns use the same saved profiles/reward and do not create another asset. Crash checkpoints are recorded locally; public evidence contains no credentials.

A separate Godot test runs the actual client HTTP path and confirms its campaign `attack()` subtracts **52 HP** after verified equip, reverts during transfer, and exposes the same asset to B. This is an automated integration test, not a manual playthrough.

`check_outages.py` really stops/restarts electrs and proxy, rejects equip/send while unavailable, then kills the launcher-owned API after Godot equips a real sword. Godot loses its lease, displays disconnection and restores its 22-damage ordinary weapon. Services are restored in `finally`/launcher cleanup.

Current public evidence:

- `evidence/managed-e2e.json`: real regtest asset, award txid, A→B txid, balances, stages and checks.
- `evidence/managed-godot.json`: actual Godot item and combat-stat verification.
- `evidence/outages.json`: real service outage/recovery checks.
- `evidence/managed-sender.png`, `managed-recipient.png`, `trial.png`, `backend-offline.png`: actual renderer output.

Regtest txids are not public Bitcoin mainnet transactions and cannot be looked up on mainnet explorers. Earlier `rgb-regtest.json` and `economy-regtest.json` are historical SDK/operator demonstrations; they do not substitute for the managed-player tests. Legacy manual mint rejects any reward already represented by a managed instance.

No barter, atomic swap, independent player keys, external-wallet deposit, mainnet support, or production account recovery is implemented. MockRGB is restricted to isolated adapter tests and cannot supply a transaction ID or verified ownership.

## Test profile isolation and corrective return

Migration 0003 adds `players.is_test`, default false. Automation explicitly registers with `is_test: true`; recipient lists and new transfer requests are restricted to the authenticated profile's purpose. Account purpose cannot be changed by replaying registration. Existing local automation identities were classified using `scripts/classify_test_profiles.py`, which verifies saved bearer-token hashes and refuses IDs present in the ordinary profile file. Classification changes account metadata only, never asset ownership.

The authorized correction for sword #4 was executed before enabling the cross-purpose restriction: actual test-wallet A → ordinary-wallet A transfer, preserving its serial/asset. `scripts/restore_sword4.py` is a narrowly scoped, idempotent record of this specific repair, not a general bypass endpoint. `docs/evidence/sword4-return.json` contains the native wallet verification and transaction ID. Future accidental cross-purpose transfers are rejected server-side even if a stale client submits a hidden test recipient.
