# Bram, the local AI blacksmith

This feature belongs to the **native Godot `main` branch**. Bram stands beside an anvil at **(800, 720)**, east of the Keeper in Emberfall, on the road toward the crypt. Approach him and press **E**. Enter sends a message; Esc closes the dialogue. Movement, attacks and gameplay hotkeys pause while the dialogue is open. A reply can finish after you close it.

## Start

For a clean machine, follow [NEW_LAPTOP.md](NEW_LAPTOP.md) before this feature-specific guide.

Install Node **22.17+** and npm **10.9+** in addition to the existing Docker, Python and Godot prerequisites. From the repository root:

```sh
./scripts/start.sh
```

The launcher installs the pinned `@qvac/sdk@0.21.1` from `npc/qvac/package-lock.json` when needed, starts QVAC on loopback port **8790**, the existing API on **8787**, the RGB worker and the desktop game. It preserves existing data. If an older game process is already running, save with F5, close it and run the command again; the launcher does not kill an unsaved game to reload scripts.

The first model download needs approximately **2.50 GB** plus runtime/cache space. Open Bram's dialogue to see download percentage and byte progress from `loadModel.onProgress`, followed by loading and ready states. The game remains playable while loading. Internet is needed for dependencies and the initial model download; inference runs locally afterward. Model weights are cached in `.state/npc/models/`. No cloud inference or simulated answer is used if loading fails.

Runtime: `QWEN3_4B_Q4_K_M` (Qwen3 4B, quantized Q4_K_M), an 8,192-token model context, no tools, no shared KV cache, at most one native generation at a time. The smaller 1.7B model from the example was evaluated but confused numbered RGB items with ordinary gear, so it is not the selected runtime model. The SDK version and RGB stack were not upgraded. Model answers remain fallible advice; ownership and equipment always use the existing authoritative API, never model text.

`QVAC_DEVICE=cpu ./scripts/start.sh` selects CPU when starting a new sidecar. Device changes require stopping the existing sidecar first; ordinary repeated launches reuse its process. Loading errors are shown in the dialogue. The Retry button retries a failed model load or message as appropriate. Logs are in `.state/qvac.log` and `.state/api.log`; prompts, answers, player tokens and wallet secrets are not logged by the integration.

## Data and authority

```text
Godot dialogue -> authenticated FastAPI -> loopback QVAC service -> local Qwen
                         |
                    profile-scoped PostgreSQL history
```

- The backend chooses the profile from its bearer token. Dialogue requests cannot supply another player ID or an asset ID.
- The model receives an allowlist: ordinary item names/stats, at most eight related registered item instances with their stats and current eligibility, current RGB equipment, at most eight related operation states, the latest trial state, and bounded campaign stats reported by Godot. No player UUIDs/names, wallet fingerprints, asset IDs, invoices, transaction IDs, authentication tokens, seeds or signing keys are added to model facts.
- Campaign stats are explicitly marked **client-reported**. They cannot prove ownership. The existing `usable()` check supplies RGB eligibility from service health, ownership, instance state and recent wallet verification. Taking this read-only snapshot does not grant or renew an equipment lease.
- Facts describe a snapshot when the message is sent. A transfer can change state while the model answers; the item screen remains authoritative. Previous conversation facts are explicitly subordinate to current facts.
- Bram is instructed to answer in English, briefly and in character, acknowledge missing facts, distinguish campaign gold from RGB items, and explain the trial. Numbered instances have an explicit name/damage/eligibility ledger to avoid confusing them with campaign swords. Structured generation and an output validator reject malformed, excessive or non-ASCII replies with an English retry error. This is not a general proof of language or factual correctness.
- No model function, tool, wallet adapter or action dispatcher exists. Requests to forge, equip or send can only produce advice. Even malicious model output is displayed as plain text, never interpreted as code, markup or an operation.
- Dialogue text is stored locally in the game database. Do not paste secrets into chat: your own text is necessarily sent to the local model. The service's internal bearer key is generated in `.state/npc/service.key`, mode 0600, never exposed to Godot or committed. The service rejects browser Origin requests and binds only to loopback. This is a local desktop feature, not a hardened multi-tenant deployment.

## History, requests and recovery

`npc_conversations` and `npc_messages` are added by Alembic **0004** without altering wallet tables. Each profile retains at most **12 turns**. At most three completed turns are selected for inference, further bounded to **1,200 UTF-8 bytes**. The current input is capped at 600 characters; generation at 220 tokens and 600 output characters.

Every turn has a profile-scoped request key. Repeated Enter/Send and retries reuse the existing turn; a second distinct in-flight turn is rejected. Retention prunes old turns and their keys together. Clearing history deletes that profile's turns and advances a revision so delayed old requests cannot recreate them. A late completion after Clear is discarded. Switching profiles cancels the client's old HTTP request and drops its draft; another profile's response is never rendered.

The API returns a job immediately, and Godot polls with a separate HTTPRequest, independent of wallet refresh. Timeouts: 8 seconds for Godot API calls, 60 seconds for inference, 70 seconds for the backend's sidecar call, 15 minutes for model loading. An uncertain HTTP delivery retains the same request key. Native cancellation retains the generation slot until the SDK request settles. If native cancellation itself hangs, restart the QVAC process; it is not safe to start a second generation in that slot.

On API startup, unfinished turns become failed with a restart error and can be retried. Completed history persists. A QVAC outage produces an offline/error state, never a canned answer. Restarting reuses cached model weights. The RGB worker and campaign continue independently.

API endpoints, all requiring the current player's token:

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/npc/blacksmith` | Own history, revision, actual service/model state |
| POST | `/api/npc/blacksmith/messages` | Enqueue a bounded read-only turn |
| DELETE | `/api/npc/blacksmith` | Clear own history with revision check |
| POST | `/api/npc/blacksmith/load` | Retry loading the local model |

## Reproduce verification

```sh
./scripts/start.sh --no-game
.venv/bin/python -m pytest backend/tests -q
npm --prefix npc/qvac test
.venv/bin/python scripts/check_blacksmith.py --outage
RUNEFORGE_BLACKSMITH_EVIDENCE="$PWD/docs/evidence/blacksmith-godot.json" \
  ./scripts/play.sh --headless --script res://tests/blacksmith_check.gd -- --blacksmith-check
./scripts/play.sh --headless -- --smoke
```

The Python integration check uses **actual QVAC inference**, two persistent test profiles, and existing registered sword facts without issuing, equipping or transferring items. `--outage` briefly stops only the launcher's QVAC process, then restores it; avoid running it while someone is chatting. Crash recovery uses a separate API on **8792**, an isolated SQLite database and the same real QVAC model, leaving the main PostgreSQL/API process running. Test credentials remain under `.state/npc/`.

The Godot test sends Enter through the engine's input pipeline and waits for the real model response. It checks movement/hotkey suppression, Esc, duplicate clicks, profile isolation, history restore, layout bounds and backend disconnection/reconnection. It uses dedicated `user://blacksmith_test_profiles.json`, marked as test profiles, and writes campaign saves only to the smoke-save path.

Backend/Node unit tests use explicit inference fixtures where needed to exercise errors and concurrency; those fixtures are **not** model-integration evidence. Public real-run results belong in [blacksmith-api.json](evidence/blacksmith-api.json), [blacksmith-godot.json](evidence/blacksmith-godot.json) and [blacksmith-download.json](evidence/blacksmith-download.json). Manual visual/click testing has not been performed: Computer Use access to Godot was previously denied. Headless layout/input checks do not replace manual visual verification.

## SDK compatibility and sources

The neighboring `rgb-hackaton/apps/local-client/src/qvac.ts` was inspected as a reference; no runtime imports or paths point into that project. Signatures were checked against installed SDK 0.21.1 declarations and official sources:

- [QVAC JavaScript/TypeScript SDK](https://docs.qvac.tether.io/sdk/js-ts-sdk/)
- [Text generation and the canonical `CompletionRun.final` interface](https://docs.qvac.tether.io/sdk/ai-capabilities/text-generation/)
- [Download lifecycle](https://docs.qvac.tether.io/sdk/models/download-lifecycle/)
- [Cancellation](https://docs.qvac.tether.io/sdk/runtime/cancellation/)
- [API reference](https://docs.qvac.tether.io/sdk/reference/api/)
- [Qwen3 4B model card](https://huggingface.co/Qwen/Qwen3-4B)

Calls used: `loadModel({modelSrc, modelConfig, onProgress})`, `completion({modelId, history, kvCache:false, responseFormat, generationParams, captureThinking, stream})`, `await run.final`, `cancel({requestId})`, and `unloadModel({modelId, clearStorage:false})`. The SDK's pinned catalog descriptor supplies the model source, byte size and SHA-256 checksum; model files are not vendored in Git.
