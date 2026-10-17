# Run RuneForge on another laptop

This guide starts a **new local game installation**, including the native Godot client, Python API, local QVAC/Qwen and an isolated Bitcoin/RGB regtest stack. Use branch **main**. Nothing imports code from the neighboring rgb-hackaton project.

## Platform and prerequisites

The complete application has been tested on **Apple Silicon macOS**, with Godot **4.4.1**, Python **3.14**, Node **25.8.1** and npm **11.11.0**. Match those versions for the closest reproduction. The project's Node minimum is 22.17 and npm minimum is 10.9.

Install these before running the launcher:

| Tool | Setup |
|---|---|
| Git | Install Git, or the macOS Command Line Tools if Git is missing. |
| Python | Install Python 3.14 from [python.org](https://www.python.org/downloads/); confirm `python3 --version`. Use a normal native interpreter, not a copied virtual environment. |
| Docker | Install and open [Docker Desktop](https://docs.docker.com/desktop/). Wait until the engine is running. On Linux, Docker Engine with the Compose plugin is sufficient. |
| Node and npm | Install a supported Node release from [nodejs.org](https://nodejs.org/en/download); confirm the versions below. The launcher installs the pinned QVAC SDK itself. |
| Godot | Download the **standard** Godot 4.4.1 editor from the [official archive](https://godotengine.org/download/archive/4.4.1-stable/). No .NET edition, export templates, or editor plugins are needed for native play. |

QVAC's published requirements include macOS 14+; Linux has additional runtime/driver requirements. See the [official QVAC requirements](https://docs.qvac.tether.io/sdk/system-requirements/). The selected model is Qwen3 4B Q4_K_M, about **2.50 GB** downloaded. Allow additional disk space and memory for Docker images, containers, model runtime, Python packages and the database; the model file size is not the total memory requirement.

**Windows:** the current launcher is a POSIX shell/Python implementation using `fcntl`, `ps` and Unix signals. It does **not** run directly in PowerShell or CMD. WSL2 with Linux tooling and a working graphical Linux Godot session is a possible development route, but it has not been validated for this complete game. Native Windows one-command support is not implemented. SDK platform support alone does not establish game launcher compatibility.

**Linux / Intel Mac:** not end-to-end tested for RuneForge. The pinned RGB release publishes wheels for macOS arm64/x86-64 and glibc Linux arm64/x86-64; check your architecture against the [actual release files](https://pypi.org/project/rgb-lib/0.3.0b7/#files). Keep `rgb-lib==0.3.0b7`; do not substitute another RGB stack. For QVAC on Linux, follow the linked driver/runtime prerequisites, including `libatomic1`. Intel Mac inference uses the CPU.

## 1. Get the current desktop source

On the new laptop:

```sh
git clone --branch main https://github.com/yolki-palki-team/rgb_game_02.git
cd rgb_game_02
```

The clone folder can have any name. Commands below run from that folder. Check that this copy includes the blacksmith before continuing:

```sh
git branch --show-current
git log -1 --oneline
test -f npc/qvac/package.json
test -f game/scripts/blacksmith_dialogue.gd
```

If either `test` command exits with an error, that clone does not contain the new feature. The developer must commit and push the current implementation to this repository's main branch, after which you can `git pull --ff-only`. Files that exist only as uncommitted changes on another laptop cannot arrive through `git clone` or `git pull`.

Do not copy `.venv`, `npc/qvac/node_modules`, `game/.godot` or `.state/processes.json` from the old laptop; these contain machine-specific dependencies, caches or process IDs. A fresh clone intentionally excludes them.

## 2. Configure Godot and verify installed tools

On macOS, unpack `Godot.app` into Applications, open it once normally if macOS asks to approve the downloaded app, then set the executable path in the same terminal:

```sh
export GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT_BIN" --version
```

On Linux, set `GODOT_BIN` to the absolute path of the downloaded executable, or put an executable named `godot` / `godot4` on PATH. If you use a different folder or rename the app, adjust the path. The environment variable points at the executable **inside** the macOS app bundle, not the bundle itself. See [Godot command-line usage](https://docs.godotengine.org/en/4.4/tutorials/editor/command_line_tutorial.html).

Verify all tools:

```sh
python3 --version
node --version
npm --version
docker compose version
docker info
```

The checked versions must meet the prerequisites. A failing `docker info` means the engine is not ready or your account cannot access it.

## 3. Prepare the environment and import game assets

Run once for a fresh clone:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r backend/requirements.txt -r backend/requirements-rgb.txt
./scripts/play.sh --headless --editor --import --quit
```

The last command builds Godot's local import cache from the committed PNG/WAV assets. This step matters because `game/.godot` is intentionally not in Git. Alternatively, open `game/project.godot` in the Godot editor and wait for imports to finish before playing.

Use `python3 -m pip`, or the `.venv/bin/python -m pip` command above, rather than relying on a global `pip` command. The launcher can create a missing virtual environment automatically, but if installation fails halfway, rerun the explicit install command above to repair the existing environment.

No cloud AI key, paid service, production wallet, seed phrase, or neighboring checkout is needed. Do not import somebody else's wallet to start playing. `.env.example` is informational; the launcher does not automatically load a `.env` file.

## 4. Start the complete game

With Docker running and `GODOT_BIN` still set if needed:

```sh
./scripts/start.sh
```

The launcher starts four infrastructure containers (PostgreSQL, Bitcoin regtest, electrs, RGB proxy), applies database migrations, then starts FastAPI, the managed-wallet worker, local QVAC and Godot. The required Docker images and QVAC dependencies are downloaded when missing. The Compose project is named `runeforge`; it is a single installation per machine by default, not an independent stack per checkout folder.

Choose **Begin Journey**. Walk east of the village Keeper to **Bram and his anvil**, and press **E**. The dialogue shows initial model download progress and loading state. Wait for **Ready**, enter a question and press Enter. Esc closes the dialogue; the model can finish loading while you keep playing. Future launches reuse the model cache.

Press **R** for the Oath Trial and RGB items. Win the server-validated trial to earn a new sword. **Player A** and **Player B** are separate profiles/wallets on this installation. The backend/worker issues and delivers the real regtest UDA automatically. They do not connect to another laptop's profiles merely because the names match.

For later launches, the normal command is again `./scripts/start.sh`. Keep `GODOT_BIN` configured in each new terminal if Godot is not on PATH. Save with F5 and close an older running game before relaunching after a code update; the launcher preserves an existing game process.

## 5. Check that everything started

```sh
curl --fail http://127.0.0.1:8787/health
curl --fail http://127.0.0.1:8790/health
docker compose --profile rgb ps
```

The first response should report the RuneForge application, real RGB mode and regtest. It confirms the API/database, not settled wallet ownership. The second reports the actual QVAC model state: `downloading`, `loading`, then `ready`. Open **R** in the game to verify that the wallet worker/infrastructure is connected. The model may be `generating` while a reply is running.

Logs live in `.state/api.log`, `.state/worker.log`, `.state/qvac.log` and `.state/game.log`. For example:

```sh
tail -n 60 .state/game.log
tail -n 60 .state/qvac.log
```

Useful variations:

```sh
./scripts/start.sh --no-game   # Infrastructure, API, worker and QVAC only
./scripts/play.sh             # Game only, using an already running stack
./scripts/check.sh            # Local automated checks, not a full manual playtest
```

Full blacksmith verification is documented in [BLACKSMITH.md](BLACKSMITH.md). Real RGB reward/transfer verification is in [RGB.md](RGB.md) and the main README; it intentionally creates or reuses test profiles.

## Troubleshooting

| Symptom | What to check |
|---|---|
| `Godot 4.4+ is required` | Set `GODOT_BIN` to an executable, then run `"$GODOT_BIN" --version`. Godot is not downloaded by the launcher. |
| Missing textures or imported resources | Run the one-time editor import command in step 3. |
| No compatible `rgb-lib` distribution | Check native OS/architecture and the exact pinned release's wheels; do not silently upgrade RGB. |
| Missing Python module after an interrupted install | Rerun the explicit pip install from step 3 in the existing `.venv`. |
| Docker daemon or image pull error | Start Docker, check network access to the container registries and retry. Do not delete volumes to fix a connection problem. |
| QVAC unavailable | Confirm Node/npm versions, inspect `.state/qvac.log`, and rerun startup. The ordinary campaign still works; no fake AI response is substituted. |
| Qwen fails to load | Check available disk/memory and platform prerequisites. Use Retry in Bram's dialogue. CPU-only startup can be selected with `QVAC_DEVICE=cpu` when starting a new sidecar. |
| Port already in use | Check for another local RuneForge stack or service. Defaults are 8787, 8790, 55432, 18543, 51001 and 3100. The launcher does not take over an unmanaged server. |
| Model downloads again on another machine | Expected: the cache is local and excluded from Git. |
| No old sword or campaign save | Expected for a fresh installation; see below. |

## A new installation is not an account/wallet migration

A fresh clone creates its own database, regtest chain, wallets and profiles. It does **not** include the old laptop's swords, campaign progress, conversations or keys. The two separate regtest networks are not a shared multiplayer server. Copying a screenshot, asset ID or profile name cannot establish ownership on the new installation.

Preserving an existing installation on another machine is a separate coordinated backup/restore task involving the PostgreSQL and Bitcoin Docker volumes, RGB wallet/state directories and Godot's user data. Do not copy just a wallet seed or a `.state` folder and assume that the game database and chain have moved with it. Never upload those secrets to GitHub.

Validation of this guide: requirements were checked against the actual launcher, SDK documentation and release wheels; dependency resolution was checked on the existing Apple Silicon Mac. Godot first-import/campaign checks can be run against a separate cache-free copy. A complete install on a second physical laptop, Linux or Windows has **not** been claimed as tested.
