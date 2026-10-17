# RuneForge — Godot / WebAssembly

The original Godot game exported to real WebAssembly with Godot 4.4.1 and the matching official single-thread web templates. Requires WebGL 2 and WebAssembly. The interface and player-facing API messages are in English.

## Run this browser version

With Docker running, from the repository root:

```sh
./scripts/start_web.sh
```

Open **http://127.0.0.1:8081**. The command starts the isolated regtest infrastructure, backend, wallet worker, and HTTP server. Git worktrees reuse the backend and persistent wallet data from the original repository. Repeated launches preserve data. If the backend is already running, use `./scripts/web.sh`.

Browser profiles **WASM A / WASM B** are separate from native Player A / Player B. Saves and API credentials are tied to the browser origin; clearing site data removes access to those browser profiles. RGB wallet keys remain on the local Python server. To transfer a sword, complete the Oath Trial, equip the reward, select the other browser profile as recipient, confirm, and wait for real settlement before switching profiles.

The first WASM build downloads about 1.15 GiB of official export templates and caches them. Set GODOT_BIN to a Godot 4.4.1 binary if needed. Generated exports in web/dist are not committed.

### Browser checks and limits

```sh
python3 web/tests/test_server.py
python3 scripts/build_web.py
python3 scripts/web_regtest.py --label webassembly --url http://127.0.0.1:8081
```

The HTTP check uses separate test profiles and real RGB wallets. It verifies victory, issuance, equipment, transfer, unchanged asset_id, sender revocation, and recipient equipment. Credentials stay in ignored `.state` files. [Recorded HTTP evidence](docs/evidence/web-api-webassembly.json) predates this translation and is not a manual browser test.

The complete browser test is available in `web/tests/browser.cjs`. Start `./scripts/web.sh --port 18081 --qa` in a separate terminal, then run:

```sh
npm ci --prefix web
cd web
npx playwright install chromium
WEB_URL=http://127.0.0.1:18081 npm run test:browser
```

**Full browser and manual UI verification remain incomplete:** Computer Use access to Chrome was denied, and browser automation was stopped. Earlier browser launch checks succeeded; HTTP integration passed independently. The English update was checked through code-level tests and Godot import, headless smoke, and web export, not a new manual browser session. Existing screenshots show the earlier language version. Desktop keyboard and mouse are required; touch controls are not implemented.

Further implementation notes: [docs/WEB.md](docs/WEB.md).

---

# Native game and shared backend

A playable dark-fantasy RPG built with Godot 4, featuring real unique RGB swords on an isolated Bitcoin regtest network. Explore a village and dungeon, fight enemies and a boss, collect loot, equip items, and save your campaign. Campaign gold is ordinary game currency, not an RGB token.

The game interface and player-facing API messages are in English. Existing saves, profile IDs, wallet keys, item instances, and RGB asset IDs are preserved. Custom player names are displayed as entered.

## Versions

All versions include the Python/FastAPI backend and real RGB integration:

| Branch | Game client |
|---|---|
| [main](https://github.com/yolki-palki-team/rgb_game_02/tree/main) | Native Godot game |
| [feature/webassembly](https://github.com/yolki-palki-team/rgb_game_02/tree/feature/webassembly) | Godot exported to WebAssembly |
| [feature/javascript](https://github.com/yolki-palki-team/rgb_game_02/tree/feature/javascript) | Standalone JavaScript / Canvas 2D client |

![Flame Sword in the recipient inventory; historical capture before English localization](docs/evidence/managed-recipient.png)

## Run the native game

Requirements: Docker Desktop or Docker Compose, Python 3 with a compatible `rgb-lib` wheel, and Godot 4.4 or newer. The WebAssembly branch requires Godot **4.4.1** and matching export templates.

From the repository root, with Docker running:

```sh
./scripts/start.sh
```

The launcher starts the isolated `runeforge` infrastructure, applies database migrations, and starts FastAPI, the wallet worker, and Godot. Repeated launches reuse existing processes and data; they do not delete Docker volumes or create duplicate profiles or rewards. If needed, the launcher creates `.venv` and installs the backend dependencies.

Set `GODOT_BIN=/path/to/godot` if Godot is not on your PATH or in `tools/godot`. To install dependencies into an existing virtual environment:

```sh
.venv/bin/python -m pip install -r backend/requirements.txt -r backend/requirements-rgb.txt
```

- API documentation: http://127.0.0.1:8787/docs
- Health check: http://127.0.0.1:8787/health
- Logs: `.state/api.log`, `.state/worker.log`, `.state/game.log`
- Services only: `./scripts/start.sh --no-game`
- Game only: `./scripts/play.sh`

Without the backend, the local campaign remains playable and RGB equipment is unavailable. There is no automatic fallback to simulated transfers.

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
| E | Interact with Keeper, portal, chest, or shrine |
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
