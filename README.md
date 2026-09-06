# Dragons Gate Player HUD

The independently versioned Player edition of the bronze-and-jade Mudlet 5 HUD for Dragons Gate. It displays confirmed `Char.Status`, `Char.Vitals`, and `Room` GMCP values, including `weapon_readied` and `shield_readied`.

The header shows the player's local computer time and a synchronized Dragons Gate clock. Game time advances at the configurable 2× default, labels 6:00 AM–5:59 PM as `Daytime` and 6:00 PM–5:59 AM as `Night`, and resynchronizes from startup or manually entered `time` output.

The compact `OPTIONS ▾` control immediately left of Real Time opens a responsive options menu. Every highlight is on by default and can be toggled independently: room titles, exits/directions, currency, travel objects, attacks aimed at you, damage received, danger/movement blocks, recovery, ongoing costs, spell threats, and discoveries/loot. Normal room prose and chat remain unchanged. Preferences survive HUD reloads and updates without changing personal Mudlet triggers or colors.

The HUD tracks posture from confirmed game output using the mutually exclusive global variables `standing` and `sitting`. Both begin unknown. Standing messages set `standing=true`; seated, lying, fallen, fainted, and passed-out messages set `sitting=true`. Merely being off balance, knocked back, seeing `You fall...`, or being told to stand does not change posture. The separate `unconscious` variable follows confirmed loss and recovery of consciousness. Matching is substring-safe so command echo and optional social wording do not prevent updates.

The OG Dragons Gate autoroller is built into DGHUD. It scores `Awful` through `Great` as 1–7 across STR, INT, WIS, DEX, AGI, CON, CHA, WIL, VOI, PER, and APP. It starts at the Name/Race body-generation line, sends only `n` for rejected rolls, and leaves a qualifying `Y,n` prompt untouched for manual acceptance. Initial settings match the source DGC Staff roller: target 53, hard stop 62, 0.1-second rerolls, minimum rank 5 for every stat, and session plus master logs under the profile's `DragonsGateHUD/og_dg_roller` directory. The `OPTIONS ▾` menu includes every roller command and a responsive settings form for all roller values; Save validates and persists the complete form without editing scripts. Typed commands remain available: `rr start|stop|stats|last|reset|help`; adjust individual settings with `rr set total 60`, `rr set hard 70`, `rr set max 10000`, `rr set delay .5`, or `rr set STR 5` (use `off` to clear an optional limit).

```text
dghud colors
dghud colors room off
dghud colors exits on
dghud colors currency toggle
dghud colors damage toggle
dghud colors spell off
```

The setting is stored as `DGHUD.user_settings.colorization.enabled`. Integrations can read it with `Settings.colorEnabled(settings)` and update only that override with `Settings.setColorEnabled(DGHUD.user_settings, enabled)`.

Run `dghud help` to open the scrollable, color-coded command guide. Everyday commands are green, descriptions are neutral, and potentially destructive package/map cleanup commands are red. The guide closes with its `× CLOSE` button and remains open and properly bounded during window resizing.

The HUD runs `info mag` during character startup and whenever the command is entered manually. All elemental runes are retained, sorted by lowest remaining weaves first, and shown in a five-row scrollable Runes card above Skills. Trigger scripts can read `DGHUD.runes.items`, `DGHUD.runes.by_name["force"].remaining`, `DGHUD.runes.remaining.force`, `DGHUD.runes.get("force")`, or `DGHUD.runes.getRemaining("force")`.

## Local build and install

```bash
python3 scripts/build.py --owner wizzydizzy-ctrl --repository dragons-gate-player-hud
```

In the Dragons Gate Mudlet profile command line, replace the path and run:

```lua
lua installPackage("/absolute/path/to/dragons-gate-player-hud/dist/DragonsGateHUD.mpackage")
```

After the first GitHub release, install directly with:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/download/v0.1.0/DragonsGateHUD.mpackage")
```

This executes code from that release inside the current Mudlet profile. Use only your own repository URL.

## Publishing

Create an empty GitHub repository, set your owner in `src/defaults.lua`, commit this project, and push a semantic version tag such as `v0.1.0`. GitHub Actions tests and attaches `DragonsGateHUD.mpackage` and `manifest.json` to the release.

The HUD owns only the package named `DragonsGateHUD`, runtime IDs it creates, and files under the profile's `DragonsGateHUD` data directory. It does not alter unrelated profile triggers, aliases, scripts, timers, keys, packages, modules, maps, or settings.

## Persistent top chatbox

The always-visible top-center chatbox records approved communication formats without gagging, replacing, or otherwise changing normal game output. Its built-in filters are `ALL`, `ROOM`, `OWN`, `WHISPER`, `ESP`, `DRAGON`, `CONTACT`, and `STAFF`; `PRIVATE` shows `WHISPER`, `ESP`, `DRAGON`, and `CONTACT` together. Each entry retains its exact category even when a combined filter is used.

The default chat settings are:

```lua
chat = {
  enabled = true,
  height_percent = 0.21,
  target_height = 240,
  min_height = 160,
  max_height = 320,
  visible_limit = 1000,
  dedupe_seconds = 3,
  timestamps = true,
}
```

User overrides merge into these defaults, including nested `chat` overrides, without discarding unknown personal settings. For example, from the Mudlet command line, set an override and reload:

```lua
DGHUD.user_settings.chat = DGHUD.user_settings.chat or {}
DGHUD.user_settings.chat.height_percent = 0.25
DGHUD.user_settings.chat.timestamps = false
DGHUD.reload()
```

Setting `chat.enabled = false` disables the HUD-owned chat capture runtime. `visible_limit` bounds only memory: the disk log is never pruned by the HUD. Adjacent duplicate entries with matching category, speaker, target, and message are accepted only once within `dedupe_seconds`; later or non-adjacent repeats remain in the log.

### Custom capture triggers

Personal triggers remain yours. The HUD never creates, edits, or deletes them. A personal trigger can add a filterable custom category through the stable API:

```lua
DGHUD.chat.capture("QUEST", line)
```

Or send a message directly when the trigger already extracts the text:

```lua
DGHUD.chat.capture("EVENTS", "The invasion has started.")
```

Valid new categories automatically become available as filters. Calls made while the HUD is replacing itself during reload/update fail safely and do not send game commands or modify unrelated runtime.

### Storage, privacy, and diagnostics

Captured entries are append-only JSON Lines stored permanently under the active Mudlet profile data directory:

```text
<Mudlet home>/DragonsGateHUD/chat/<safe-character-name>/YYYY-MM-DD.jsonl
```

The HUD reads at most the newest 1,000 valid entries into memory, but leaves older dated logs intact. Reloading, updating, rolling back, or uninstalling the HUD does not delete these files. Delete the relevant files yourself if you want to remove retained history.

Private communications such as whispers, ESP, Dragon, and Contact traffic are saved locally in these plain JSONL files. Anyone with access to your Mudlet profile, computer account, backups, or copied profile data may be able to read them. The HUD does not transmit chat logs, but you should treat the directory as sensitive local data.

Run `dghud chatstatus` to print the active filter, the current visible-entry count, the sanitized current-character storage key, and the most recent storage error (`none` when no storage error has occurred in the running chat session).

Options → Feedback & Requests opens an in-game form for anonymous feedback or feature requests. The player chooses the type, enters a short summary and detailed description, and receives a reference after submission. It uses the DGHUD upload service and does not open a browser or require a GitHub account. The form warns players not to include passwords or private account information; submissions are rate-limited and published to the DGHUD GitHub project for review.

## Embedded automapper

The native Mudlet map is embedded in the lower-left HUD immediately above the compass. While the mapper is enabled, each valid `gmcp.Room.Info.num` is the canonical Dragons Gate room ID. Revisiting that GMCP number refreshes safe descriptive data on the same native room; it never creates a duplicate or relocates its saved area, partition, or coordinates. Walking through the twelve standard directions (`n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`, `up`, `down`, `in`, and `out`) discovers rooms, creates advertised exit stubs, and confirms links only after the destination room arrives through GMCP. Teleports do not invent links.

Rapidly entered directions are retained in order until each corresponding GMCP room update arrives. A failed direction removes only that queued step, so fast sequences such as `north`, `north`, `west` do not lose their origin or create accidental isolated areas.

Confirmed compass exits keep their literal visual direction. If a newly discovered west, southwest, or other directional room would occupy an existing square, the mapper expands the DGHUD-owned grid outward and reserves the exact destination square instead of placing the new room at an unrelated nearest opening. Cardinal expansion inserts a row or column; diagonal expansion shifts both outward axes. Coordinate changes are ownership-checked and rolled back together if Mudlet rejects a move. Room IDs and saved exits never change.

A confirmed special-travel command to a newly discovered destination starts a destination-rooted sub-map such as `special:900`; directional exploration remains in that partition even if Dragons Gate changes its area label. The built-in classifier accepts `go gate`, `go door`, `go portal`, `go arch`, `go path`, and conservative traversal verbs including `enter`, `leave`, `climb`, `crawl`, `cross`, `board`, and `disembark`. Normal gameplay commands cannot create phantom special exits. If the destination GMCP number is already canonical, the mapper preserves that room's saved partition and coordinates and records only the observed one-way special edge from the current origin. A command is confirmed only when a different canonical GMCP room arrives within twelve seconds. A later command replaces the candidate, and expiry, wrong direction, disconnect, reload, shutdown, or mapper disablement clears it. The mapper records only the normalized observed one-way command. It does not invent a reverse special connection; the return edge appears only after its own command and destination are observed. An untracked room change within the same GMCP area remains in the current partition without inventing an exit; only an untracked cross-area jump starts an isolated destination-rooted map.

The default mapper settings are:

```lua
mapper = {
  enabled = true,
  walk_timeout = 12,
  minimum_height = 90,
  schema = 1,
  special_timeout = 12,
  zoom_step = 2.5,
  zoom_min = 3.0,
  zoom_max = 60.0,
}
```

Nested user overrides and unknown future settings are preserved during merge and migration. Set `DGHUD.user_settings.mapper.enabled = false` and run `DGHUD.reload()` to disable discovery and walking. `walk_timeout` controls how many seconds a sent movement command waits for its expected room update. `minimum_height` sets the visible mapper floor when the window can accommodate it; wide layouts retain a 140-pixel responsive floor, while medium layouts default to 90 pixels. If the configured floor cannot fit without overlapping essential HUD content, the mapper hides cleanly.

Click a known destination in the embedded map or use:

```text
walkto 176
walkstop
mapcenter
dghud mapstatus
```

Walking sends exactly one command at a time and waits for the expected GMCP room number. Standard directions are normalized; a non-direction route step is sent only when its exact origin, destination, and command match a confirmed HUD-owned special exit. This allows `walkto` and owned native-map clicks to cross safe mixed directional/special routes without trusting an unobserved portal, door, gate, arch, or other command. After arrival, nonzero GMCP roundtime pauses the route until a later Vitals update reports zero. The per-step movement timeout is canceled while paused because no command is in flight; a fresh timeout starts only when the next command is sent. Wrong directions, unexpected rooms, manual movement, disconnection, timeout, and shutdown stop the route.

The mapper toolbar owns four controls: `−` zooms out, the center control recenters on the current canonical room, `+` zooms in, and the red `⚠ CLEAR ALL` button starts a guarded reset of every DGHUD-owned map and submap. Zoom uses Mudlet's native area-specific value, so each normal area and special sub-map retains its own level across room changes, HUD reloads, updates, and profile restarts. Configured steps and bounds are enforced independently for the current saved area.

The HUD tags only its own rooms and areas with `dghud.owner=DragonsGateHUD`. It refuses to rewrite an existing unowned room or area and never deletes personal map data. Successfully owned map data is eligible for deletion only through the explicit, confirmed cleanup controls described below; failed creations may also be rolled back transactionally. Discovered canonical rooms, partitions, observed exits, coordinates, and native per-area zoom otherwise remain when the HUD reloads, updates, or is uninstalled. `dghud mapstatus` reports only whether mapping is enabled, the current room, the number of rooms managed during the HUD session, an active walking destination, the latest mapper status, and the latest actual mapper error. Routine stops such as `walkstop`, manual movement, route replacement, and shutdown update the status but do not overwrite the last error. It does not dump room names, routes, personal map records, or unrelated data.

### Safe map cleanup

Cleanup previews require secure token entropy from `/dev/urandom`. If that source is unavailable, preview creation fails closed without changing the map. Standard Windows environments are unsupported for cleanup previews until a supported secure entropy source is added; mapping itself remains available.

To repair incorrectly generated HUD map content, run `walkstop` first. Move out of a room before deleting only that room. The current map command intentionally includes and then recreates your current room from live GMCP. Preview exactly one scope:

```text
dghud map delete room 176
dghud map clear submap 900
dghud map clear area Dragons Gate - Training Grounds
dghud map clear current
dghud map clear all
```

The red mapper button performs the same `clear all` operation. Its first click previews every DGHUD-owned area and room and changes the button to `CONFIRM CLEAR`; click it again within 30 seconds to delete that exact revalidated set. The current room is then recreated immediately from live GMCP so mapping starts fresh. Unowned and personal Mudlet map content is never included.

Inspect the resolved area and every exact room ID in the preview. If anything is unexpected, run `dghud map cancel`. Otherwise, confirm with the printed one-use command within 30 seconds:

```text
dghud map confirm <token>
```

The HUD refuses cleanup when ownership, map membership, inbound personal exits, or movement state is unsafe or has changed since preview. There is no force option. After successful cleanup, revisit the deleted canonical rooms to let normal GMCP exploration map them again. If deletion stops partway, keep the exact deleted, failed, and untouched IDs from the result, move to a safe room, and create a fresh preview before retrying.

Updating with `dghud update` replaces only the `DragonsGateHUD` package code. It preserves native map records, chat logs, user settings, and unrelated Mudlet scripts, aliases, triggers, packages, and map content.
