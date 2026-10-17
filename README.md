# RuneForge — Ashes of the Covenant

A playable dark-fantasy RPG built with Godot 4, featuring real unique RGB swords on an isolated Bitcoin regtest network. Explore a village and dungeon, fight enemies and a boss, collect loot, equip items, and save your campaign. Campaign gold is ordinary game currency, not an RGB token.

The game interface and player-facing API messages are in English. Existing saves, profile IDs, wallet keys, item instances, and RGB asset IDs are preserved. Custom player names are displayed as entered.

## Versions

All versions include the Python/FastAPI backend and real RGB integration:

| Branch | Game client |
|---|---|
| [main](https://github.com/yolki-palki-team/rgb_game_02/tree/main) | Native Godot game |
| [feature/webassembly](https://github.com/yolki-palki-team/rgb_game_02/tree/feature/webassembly) | Godot exported to WebAssembly |
| [feature/javascript](https://github.com/yolki-palki-team/rgb_game_02/tree/feature/javascript) | Standalone JavaScript / Canvas 2D client |

![Emberfall village and the English campaign HUD](docs/evidence/hub.png)

## Run the native game

**New laptop or fresh clone?** Follow [the complete setup guide](docs/NEW_LAPTOP.md) first: tools, clone, Godot path, virtual environment, asset import, first model download, health checks and platform limitations. A fresh installation gets new local profiles and wallets; old swords and saves are not included in Git.

Requirements: Docker Desktop or Docker Compose, Python 3 with a compatible `rgb-lib` wheel, Godot 4.4 or newer, and Node 22.17+ / npm 10.9+ for the local AI blacksmith. The WebAssembly branch requires Godot **4.4.1** and matching export templates.

From the repository root, with Docker running:

```sh
./scripts/start.sh
```

The launcher starts the isolated `runeforge` infrastructure, applies database migrations, and starts FastAPI, the wallet worker, local QVAC, and Godot. Repeated launches reuse existing processes and data; they do not delete Docker volumes or create duplicate profiles or rewards. If needed, the launcher creates `.venv` and installs the backend dependencies.

Set `GODOT_BIN=/path/to/godot` if Godot is not on your PATH or in `tools/godot`. To install dependencies into an existing virtual environment:

```sh
.venv/bin/python -m pip install -r backend/requirements.txt -r backend/requirements-rgb.txt
```

- API documentation: http://127.0.0.1:8787/docs
- Health check: http://127.0.0.1:8787/health
- Logs: `.state/api.log`, `.state/worker.log`, `.state/game.log`, `.state/qvac.log`
- Services only: `./scripts/start.sh --no-game`
- Game only: `./scripts/play.sh`

Without the backend, the local campaign remains playable and RGB equipment is unavailable. There is no automatic fallback to simulated transfers.

## Talk to the blacksmith

Bram stands beside an anvil **east of the Keeper**, on the village road toward the crypt. Walk close and press **E**. Ask freely about your weapons, RGB item restrictions or the Oath Trial. He answers briefly in English using local **Qwen3 4B through QVAC**, with no cloud fallback. Enter sends; Esc closes; Clear conversation clears only the current profile's history. Gameplay controls are paused while you type.

The first launch downloads approximately **2.50 GB**; real download progress appears in the dialogue and subsequent launches reuse the local cache. Bram only reads game state: he cannot mint, equip or transfer anything. His advice can be mistaken; the item screen and server remain authoritative. If the game was already open before updating, save, close it and launch again to load the new NPC.

See [blacksmith setup, architecture and real integration checks](docs/BLACKSMITH.md).

## Earn, equip, and transfer a sword

1. Choose **Begin Journey** or **Continue**, then press **R** and select **Trial**. You can also approach the glowing **Oath Trial** portal south of the village Keeper and press **E**.
2. Select **Player A**. Guard against heavy attacks, attack when safe, and rest to recover stamina. The server calculates combat and validates victory.
3. After winning, select **Track delivery**. The worker handles the real stages automatically: reward earned → UDA issuance → transfer verification and confirmations → item received. Initial wallet preparation may take about a minute.
4. Select **Flame Sword #N** and choose **Equip**. The HUD shows **52 ATK**, and campaign attacks use that damage. The starter sword deals 22.
5. Choose **Transfer**, select **Player B**, and confirm. The sword is immediately unequipped and reserved.
6. Wait for delivery, switch to **Player B**, and equip the same sword. Its instance number and `asset_id` stay unchanged; Player A loses the right to use it.

Automated test profiles are separated from regular players on the server and do not appear in their recipient lists. Profile IDs determine identity; a matching name does not establish ownership.

## Profiles and wallet custody

Player A and Player B are separate server profiles with separate RGB wallets. The switcher supports testing on one computer; the local campaign on that computer is shared. Native profile credentials are stored in Godot `user://managed_profiles.json`. These are game API credentials, **not RGB wallet keys**. Persistent registration keys make retries idempotent after a connection failure.

**The local RuneForge service holds wallet keys** in `.state/managed-v2/<player UUID>/`. This is service custody, not independent personal wallets. The game client and API responses never receive seed phrases or signing keys. Do not delete wallet directories or Docker volumes to resolve a temporary connection error.

This local MVP does not provide email account recovery, password-encrypted seed storage, or production account security. Existing built-in profile labels are displayed in English without renaming the underlying profiles or changing their registration credentials. Item catalog text is updated on backend startup without reissuing assets.

## Native campaign controls

| Input | Action |
|---|---|
| WASD / mouse | Move / aim |
| Left mouse button | Sword attack |
| Space | Dodge roll |
| Q | Drink a potion |
| E | Talk to Bram / interact with Keeper, portal, chest, or shrine |
| I | Campaign inventory |
| R | RGB items, profiles, and trial |
| Esc / F5 | Menu / save |

Speak to the Keeper, explore the eastern crypt, defeat the Shadow Guardian, and return to the village. The local legendary campaign sword and the RGB Flame Sword are different items. Editing a local save cannot authorize a server reward.

## Verification

```sh
./scripts/check.sh
TEST_DATABASE_URL='postgresql+psycopg://runeforge:runeforge_local_only@127.0.0.1:55432/runeforge' \
  .venv/bin/python -m pytest backend/tests -q
./scripts/check-managed.sh
```

The managed check uses real regtest infrastructure, separate test profiles, and real wallets. It temporarily stops the worker, checks issuance and transfers, runs the Godot scenario, and interrupts and restores electrs, the proxy, and the backend. Do not run it during your own trial or transfer. Repeated runs reuse the same item instances. The first run tests crashes after native issue/send operations; subsequent runs verify the persisted result. Godot test profiles are stored separately from regular profiles.

Recorded evidence contains no wallet secrets:

- [Real asset IDs, transaction IDs, and recovery](docs/evidence/managed-e2e.json)
- [Godot scenario and equipment damage](docs/evidence/managed-godot.json)
- [Infrastructure outages and recovery](docs/evidence/outages.json)
- [Installed RGB SDK signatures](docs/evidence/rgb-signatures.json)
- [Sender](docs/evidence/managed-sender.png), [recipient](docs/evidence/managed-recipient.png), [trial](docs/evidence/trial.png), and [transfer confirmation](docs/evidence/transfer-confirmation.png) captures

These captures predate the English localization. Earlier automated checks and rendered-image inspection passed. Manual Computer Use testing was blocked by denied access to Godot; it is not claimed as passed. The English update is checked with backend regressions and Godot headless checks; browser-specific verification is described in each browser branch.

## RGB scope and limitations

The stack remains **`rgb-lib==0.3.0b7`**, using RGB core **v0.11.1-rc.11**, on isolated **Bitcoin regtest only**. Transfers between service-managed wallets are real RGB operations. No mainnet keys or real Bitcoin funds are used. The mock adapter is reserved for isolated tests and is not part of the player workflow.

External wallets, deposits, trading, and sword-for-shield exchanges are not implemented. Two independent sends are never described as an atomic swap. Ambiguous operations stay reserved until ownership is reconciled; an uncertain issuance result must not trigger a replacement asset. Corrupted wallet state or unresolved SDK records may require local operator recovery.

See [docs/RGB.md](docs/RGB.md) for the trust model, API, and recovery procedures. Legacy operator scripts and `regtest_demo.py` remain available for diagnostics; players do not need to run them manually.
