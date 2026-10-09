# DGHUD Command Reference

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

Applies to DGHUD v0.3.96.

Use the lowercase commands shown below. Skill filters ignore case; other HUD aliases may require the exact lowercase spelling.

Most features are also available through **OPTIONS**. Destructive map commands create a preview; they do not delete immediately.

## General HUD commands

| Command | What it does |
| --- | --- |
| `dghud help` | Open the in-game scrollable command guide. |
| `dghud check` | Check the newest verified release and report the installed version without installing. |
| `dghud update` | Install a newer verified release when one exists, then refresh character data. |
| `dghud recover` | Emergency clean reinstall through the independent recovery companion. |
| `dghud safe update` | Run the installed migration bridge after a differing-personal-data warning; stop the autoroller first. See [safe-upgrade steps](UPDATES_AND_RECOVERY.md#update-stopped-safely-run-the-safe-upgrade-bridge) if the command is unknown. |
| `dghud reload` | Rebuild the currently installed HUD using saved settings. |
| `dghud refresh` | Run inventory, stat, info, religion, runes, skills, and time refreshes without reinstalling. |
| `dghud config` | Print the profile's persistent DGHUD data location. |
| `dghud chatstatus` | Report chat filter, visible count, storage key, and latest storage error. |
| `dghud text small` | Use the Small HUD text preset. |
| `dghud text normal` | Use the Normal HUD text preset. |
| `dghud text large` | Use the Large HUD text preset. |
| `dghud text status` | Report the current HUD text preset. |
| `dghud layout` | Print privacy-safe responsive-layout measurements for troubleshooting clipping or low-resolution behavior. |

`dghud purge` may appear in older built-in command text. Do not use it for routine repair or map cleanup; use `dghud recover` or the specific map commands below.

For setup and repair steps, see [Installation and First Start](INSTALLATION_AND_FIRST_START.md) and [Updates and Recovery](UPDATES_AND_RECOVERY.md). For text sizing and display controls, see [Options and Display](OPTIONS_AND_DISPLAY.md).

## Skills commands

**OPTIONS → Skill Settings → SKILL FILTERS** defaults **ON**. The argument commands below describe HUD filtering while ON. To use a native staff command such as `skill Rath`, choose **OFF** and **Save**. Every argument form, including `all`, `weapons`, `combat`, `utility`, and `train`, then passes unchanged to the game exactly once with its original casing and spacing, without a queued local filter or a busy/display-unavailable rejection. Bare `skill` still refreshes the sidebar and uses your **MAIN SKILLS** formatting choice.

**MAIN SKILLS** controls formatting separately; turning it off does not disable enabled filters. Save commits the draft; Cancel or dismissing the panel discards it. Reset restores filters ON only after Save. Failed saves keep active settings unchanged, and saving OFF cancels pending local filters. The saved choice survives other display changes, reloads, updates, and restarts.

| Command | What it does |
| --- | --- |
| `skill` | Request every possessed skill and refresh the full Skills sidebar. |
| `skill all` | Show every possessed skill, clearing any previous filter. |
| `skill weapons` | Show possessed Sharp, Blunt, Piercing, Thrown, and Missile Weapons, plus Biting, Clawing, Webbing, Breath Weapon, and Stinging. |
| `skill combat` | Show all possessed combat rows, including ready-to-train zero-use rows; green for zero uses, otherwise blue by default. |
| `skill utility` | Show all possessed utility rows, including ready-to-train zero-use rows; green for zero uses, otherwise yellow by default. |
| `skill train` | Show all zero-use rows (green by default) from either category. Display only; sends no game training command. |
| `skill <prefix>` | Show skills whose names begin with the supplied text; for example, `skill claw`, `skill bite`, `skill c`, `skill id`, or `skill ste`. |

With **SKILL FILTERS ON**, DGHUD handles the forms with an argument by requesting the full game `skill` response, then filtering only that response in the main display. The sidebar keeps every captured skill. Prefixes are literal text, ignore case, and also match supported shortened display names. `weapons` is an exact group name, not a search for every name containing “weapon”; it uses skill IDs 2–6, 46–49, and 57 and never adds skills you do not possess.

The current skill names **Piercing Weapons**, **Thrown Weapons**, and **Shield Use** retain IDs **4**, **5**, and **7**. Older output and filters using `pole`, `poles`, `throw`, `throws`, or `shield parry` still work. Formatted tables use the current names; turning **MAIN SKILLS** off preserves the game's original names and layout.

With **MAIN SKILLS** on, results use your main-display sorting, catalog numbers, and skill colors. With it off, enabled filters still work but keep the game's row format and order. When filters are ON, if a refresh or skill request is still loading, wait for it to finish, then repeat the command. If local filtering is unavailable, run `dghud reload`, then try again.

`combat`, `utility`, and `train` are exact group names, ignoring case. Combat and utility membership uses skill category regardless of remaining uses; train membership uses zero remaining uses. A zero-use row appears in its category group and in `train`. Customizing or disabling colors does not change membership. The existing `weapons` group and name-prefix filters still include matching zero-use skills. Every filter applies to one main-display response; the sidebar retains the full list.

See [Screen and Character Data → Skills](HUD_SCREEN_AND_CHARACTER_DATA.md#skills) for sorting, colors, and display controls.

## Color commands

| Command | What it does |
| --- | --- |
| `dghud colors on` | Enable the master color switch. |
| `dghud colors off` | Disable all DGHUD output highlights. |
| `dghud colors toggle` | Reverse the master color state. |
| `dghud colors status` | Print all current color states. |
| `dghud colors <feature> on` | Enable one feature. |
| `dghud colors <feature> off` | Disable one feature. |
| `dghud colors <feature> toggle` | Reverse one feature. |
| `dghud colors <feature> status` | Report one feature. |

Feature names:

```text
room exits currency races classes highlights portal presence attack damage danger recovery upkeep spell discovery illumination notice world skills
```

Example:

```text
dghud colors illumination toggle
```

See [Color Highlighting](COLOR_HIGHLIGHTING.md) for what each feature highlights and how to change its styles.

## Roundtime check

`delay` is a normal game command. Its remaining-time response stays visible when you run it manually and also corrects the HUD countdown. DGHUD may request its own throttled check after printed delay bursts; only an isolated reply proven to belong to that automatic check is hidden. See [Roundtime troubleshooting](TROUBLESHOOTING.md#roundtime-is-stuck).

## Mapper and walking commands

| Command | What it does |
| --- | --- |
| `dghud mapper on` | Enable and show the mapper. |
| `dghud mapper off` | Pause and hide mapping without deleting maps. |
| `dghud mapper toggle` | Reverse the mapper state. |
| `dghud mapper status` | Report whether the mapper is enabled. |
| `dghud mapstatus` | Report current room, managed count, walk target, latest status, and latest error. |
| `mapcenter` | Center the native map on the current canonical room. |
| `walkto <room number>` | Walk to a known mapped room. |
| `walkstop` | Stop the current automatic walk. |
| `dghud map library` | Open the built-in My Maps and Shared Library browser. |
| `dghud map folder` | Open the local map export/import directory. |

`dghud map on|off|toggle|status` is accepted as an alternate form of `dghud mapper ...`.

See [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md) for mapping, walking, imports, and cleanup steps.

## Private map backup and advanced import commands

The built-in Map Library is easier for most people. These commands remain useful for local backup files.

| Command | What it does |
| --- | --- |
| `dghud map export <name> <publisher>` | Save a validated private JSON map backup. |
| `dghud map import <name>` | Validate a local JSON map and preview room-ID conflicts. |
| `dghud map import area <area> keep` | Keep current rooms for conflicts in one area. |
| `dghud map import area <area> replace` | Prefer imported rooms for conflicts in one area. |
| `dghud map import area <area> skip` | Skip conflicts in one area. |
| `dghud map import room <number> keep|replace|skip` | Override conflict handling for one canonical room. |
| `dghud map import confirm` | Apply the exact reviewed import transaction. |
| `dghud map import cancel` | Discard the pending import preview. |

Names used by the local export command must be simple words made from letters, numbers, underscores, or hyphens. The graphical library supports friendlier display names.

## Map cleanup commands

Stop walking first. Every command below only previews DGHUD-owned data:

```text
walkstop
dghud map delete room 176
dghud map clear submap 900
dghud map clear area Dragons Gate - Training Grounds
dghud map clear current
dghud map clear all
```

After inspecting the preview, confirm its one-use token:

```text
dghud map confirm <token>
```

Or cancel it:

```text
dghud map cancel
```

Tokens expire after 30 seconds. There is no force-delete command.

## Mapper diagnostics

| Command | What it does |
| --- | --- |
| `dghud map debug` | Send a sanitized mapper diagnostic anonymously and print its reference. |
| `dghud map debug folder` | Save a private local diagnostic and open its folder. |

## Autoroller commands

| Command | What it does |
| --- | --- |
| `rr start` | Reset and start a rolling session. |
| `rr stop` | Stop automatic rolling and cancel queued work. |
| `rr status` | Explain whether the roller is active and exactly what it is waiting for. |
| `rr show` | Show every saved roller setting in clear groups. |
| `rr stats` | Show session roll count, average, best/worst rolls, and highest observed ranks beside your saved minimums. Also available as SESSION BEST in Options → Autoroller. |
| `rr last` | Show the newest captured roll. |
| `rr reset` | Clear the current roller session state and counters. |
| `rr help` | Show the short roller command list. |
| `rr set total <1-77|off>` | Set or disable the normal total target. |
| `rr set hard <1-77|off>` | Set or disable the hard-stop total. |
| `rr set max <number|off>` | Set or disable the maximum roll count. |
| `rr set delay <seconds>` | Set a zero-or-greater reroll delay. |
| `rr set greats <1-11|off>` | Set or disable the arranged-pool top-rank count. |
| `rr set goodplus <1-11|off>` | Set or disable the arranged-pool Good-or-better count. |
| `rr set arrange manual` | Leave a qualifying pool for manual placement. |
| `rr set arrange auto` | Ask the game to place a qualifying pool. |
| `rr set arrange minimums` | Place configured minimums, then ask the game to fill the rest. |
| `rr set <STAT> <1-7|off>` | Set or disable one characteristic minimum. |

Valid current stat names:

```text
STR INT WIS DEX AGI CON CHA WIL PRE PER LUK
```

See the [Autoroller Guide](AUTOROLLER.md) before changing hard-stop or automatic-placement settings.

## Normal game commands DGHUD reads

These remain Dragons Gate commands, not DGHUD aliases:

```text
inventory
inv
stat
info
info religion
info magic
skill
time
```

DGHUD observes their complete responses and refreshes the matching panel. `info mag` is also recognized as a shortened form of `info magic`. The skills forms with an argument are DGHUD aliases described [above](#skills-commands).

## Chat history commands

| Command | What it does |
| --- | --- |
| `dghud chat clear` | Clear the visible chatbox while keeping saved history. |
| `dghud chat clear saved` | Show the required permanent-deletion confirmation command. |
| `dghud chat clear saved confirm` | Permanently delete saved DGHUD profile chat history and clear the chatbox. |

The same actions are available under **OPTIONS → CHAT SETTINGS**. Saved history is retained by default and remains shared across characters in the profile.

See the [Chatbox Guide](CHATBOX.md) for tabs, sound alerts, hidden-chat behavior, and local-history privacy.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
