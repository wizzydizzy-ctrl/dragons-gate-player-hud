# DGHUD Options and Display Settings

Applies to DGHUD **v0.3.89**.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

The **OPTIONS** button is at the far left of the header. The current DGHUD version is shown beside it. Click **OPTIONS** to open a short menu of sections.

## Mudlet UI

The option is labeled **MUDLET UI** (or **MUDLET STARTER UI** in some builds). **OFF** means Mudlet's separate starter dock (extra map, chat, and vitals) is hidden; **ON** means it is shown. DGHUD defaults it off when no explicit show/hide choice has been saved, without touching the game-text window, command line, toolbar, or HUD mapper. Click the option to switch it. Mudlet remembers your choice across restarts and HUD updates. The extra dock may overlap the HUD when shown, but you can drag it by its title bar.

If that starter package is not installed in the profile, the option reports that it is unavailable and changes nothing. Mudlet's own `baseui show` and `baseui hide` commands still work; reopening OPTIONS refreshes the toggle's status.

## Chat Settings

Open **OPTIONS → CHAT SETTINGS → SHOW CHATBOX** to show or completely hide the top-center chatbox. It starts **ON**. Turning it **OFF** expands the main display without deleting history or stopping chat capture. You can reopen Chat Settings through OPTIONS even while chat is hidden. This preference survives character changes, restarts, and HUD updates.

The same window controls which sources appear in ALL, provides separate history-clearing buttons, and offers per-tab sound alerts. Under **SOUND ALERTS**, choose each tab's sound, turn it on or off, or click **PREVIEW**. Staff alerts start on; the other tabs start off. See the [Chatbox Guide](CHATBOX.md).

## Keybindings

Open **OPTIONS → KEYBINDINGS** to enable or customize the number pad. Standard movement follows the keypad compass: 8 north, 9 northeast, 6 east, 3 southeast, 2 south, 1 southwest, 4 west, and 7 northwest. Numpad 5 sends `look`, `+` sends `up`, and `-` sends `down`. The remaining keypad keys are editable and begin blank.

On Windows, keep Num Lock on. On macOS, use the actual numeric keypad; the number row above the letters is not the keypad. DGHUD creates temporary bindings that it owns and removes only those exact bindings when it reloads. If a requested key is already assigned in Mudlet, DGHUD leaves its whole keypad set inactive and reports the collision instead of replacing a personal key. Saved choices are stored outside the package and survive updates.

## Help & Commands

**HELP & COMMANDS** opens a scrollable, color-coded command list.

- Green commands are normal tools.
- Red commands can remove HUD-owned package or map data and deserve extra care.
- **COPY** copies the complete command list so you can paste it into notes or a message.

The same panel opens with:

```text
dghud help
```

For more explanation than the in-game panel can hold, see the [Command Reference](COMMAND_REFERENCE.md).

## Refresh Character Data

**REFRESH CHARACTER DATA** runs the normal character-information sequence again. Use it when inventory, skills, runes, religion, combat information, characteristics, needs, or time looks stale.

Equivalent command:

```text
dghud refresh
```

This is not an update. It does not contact GitHub or reinstall the HUD.

## Automatic Updates

The button shows whether automatic updates are **ON** or **OFF**. The default is off.

When enabled, DGHUD checks for and applies a newer verified release after character entry, then refreshes character data. When disabled, login performs only the character-data refresh. Your selection is saved outside the replaceable package and is not reset by an update.

For the most predictable experience, leave this off and use:

```text
dghud check
dghud update
```

See [Updates and Emergency Recovery](UPDATES_AND_RECOVERY.md).

## HUD Text

The **HUD TEXT** button cycles through:

- **Small**
- **Normal**
- **Large**

It changes text in HUD cards and lists. It does not change Mudlet's normal game-console font.

Equivalent commands:

```text
dghud text small
dghud text normal
dghud text large
dghud text status
```

The setting is saved and survives updates.

## Main-window word wrap

**AUTO MAIN WRAP** defaults to **ON**. In that mode, DGHUD recalculates Mudlet's main game-window wrap width whenever the window is resized so room text follows the usable center display.

Turn **AUTO MAIN WRAP: OFF** when you want to control Mudlet's main-window wrap manually. Once it is off, DGHUD stops changing that value during resizing, reloads, and updates. Set your preferred wrap normally in Mudlet's profile preferences; the OFF choice is saved outside the package and survives updates.

## Skill Settings

### Show just the skills you want

Enter `skill` or `skill all` for the full list. To narrow the main console output, add the beginning of a skill name:

- `skill claw` or `skill clawing` — Clawing.
- `skill bite` — Biting.
- `skill weapons` — Sharp, Blunt, Pole, Throw, and Missile Weapons, plus Biting, Clawing, Breath Weapon, Webbing, and Stinging; only skills you have are shown.
- `skill c` — all your skills beginning with C.
- `skill id` — all your Identify skills; `skill id weapon` narrows to Identify Weapon Quality.
- `skill s` — all your skills beginning with S.
- `skill ste` — Stealth, plus any future skill beginning with Ste.

Matching ignores case and accepts full names or shortened display names. Apart from the special `weapons` group, this is a literal prefix search, not a regular expression. Longer prefixes narrow the result. No matches produces a clear message instead of a blank list. Each command requests fresh data and saves every skill to the right-hand list, even though the main output is filtered. Your sorting, columns, and skill colors still apply when formatting is on; filtering also works with formatting off. The filter applies to one response only. If character data or a previous filtered list is still loading, wait for it to finish and try again.

Open **OPTIONS → Skill Settings** to control skill formatting and sorting. **MAIN SKILLS** stays on by default and formats complete `skill` responses in aligned **Number / Skill / LVL / USES** columns. Turn it off to keep future responses in the game's original layout.

**Main Display** and **Right Sidebar** have independent sorting choices. For each, choose a primary key: **Level**, **Uses**, **Name**, **Number**, **Ready to train (0 uses)**, or **Category (combat vs utility)**. Choose ascending or descending order, and optionally add a secondary key with its own direction. Both displays default to **Level descending**, then **Uses ascending**. For “level then uses,” choose **Level** as the primary key and **Uses** as the secondary key.

Changing **Right Sidebar** ordering immediately reorders its existing skill rows. **Main Display** ordering applies to the next complete `skill` output; previously printed tables stay as they are. Formatting and sorting choices are saved for the whole Mudlet profile and survive character changes, reloads, restarts, and HUD updates.

**Number** is the game's fixed catalog ID used for training, not a display rank. All captured skills remain visible; Category and Ready to train sorting only change their order.

Rows with **0 uses remaining are green**, combat skills are **blue**, and utility skills are **yellow**. Zero uses overrides the normal category color. Use **COLOR SETTINGS → TEXT STYLES → Skills** to change the three styles, or the **SKILL ROW COLORS** category to switch their coloring off without disabling the aligned layout.

Tables ending in blank lines update on the next UI tick without waiting for a later prompt. The sidebar keeps its existing layout. See [Skills](HUD_SCREEN_AND_CHARACTER_DATA.md#skills).

Each filtered request still asks the game for fresh skill data, so wait for that response; filtering cannot display a result before the server sends it. v0.3.89 fixes the leftover blank gap after rows are hidden and refreshes the visible tail locally without sending extra Enter prompts or pulling you out of scrollback.

## Align command input

Turn **OPTIONS → ALIGN INPUT: ON** to line up the command input's **left edge** with the main game display. It follows the window as you resize it. The input ends before Mudlet's native Search and status controls, which stay visible together on the right. Search remains on the right; this does not align the input to the full width of the main display. The default is **OFF**, and your choice survives updates and restarts independently of automatic word wrap.

This keeps Mudlet's native input, command history, current draft, and aliases. Turn the option **OFF** to restore the prior input stylesheet and compact-input preference, including the previous visibility of Search and status controls. Requires Mudlet 5.0 or newer.

## Color Settings

**COLOR SETTINGS** opens individual toggles for room titles, exits, currency, races, professions, travel objects, combat warnings, recovery, spell threats, discoveries, and illumination.

The **CUSTOM WORDS/PHRASES** section lets you add, edit, or delete your own literal text matches. Each one can have its own text color, background highlight, bold, underline, and on/off choice. Saved entries stay with your Mudlet profile across character changes and HUD updates.

You can save up to **1,000** custom entries. **TEXT STYLES** also separates travel objects, other room objects, and the `is here` / `are here` wording, so each can use a different color.

All highlights are enabled by default. Turning a highlight off changes only DGHUD's coloring; it does not suppress game text.

See [Color Highlighting](COLOR_HIGHLIGHTING.md).

## Map Settings

**MAP SETTINGS** contains:

- automapping on or off;
- opt-in separate-submap choices for gates, portals, doors, arches, paths, and other special travel; all default to OFF;
- map height and zoom settings;
- walking and special-travel timeouts;
- area and subarea naming;
- map cleanup controls; and
- the built-in Map Library.

Map cleanup and replacement actions use previews and confirmations because they modify DGHUD-owned map data.

See [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md).

## Autoroller

**AUTOROLLER** opens all roller settings and controls in one place. You can set score targets, per-characteristic minimums, arranged-pool rules, safety limits, delay, output, and logging without editing a script. Use **WHAT IS IT WAITING FOR?** if rolling appears paused, and **SHOW SAVED SETTINGS** to verify the active configuration.

Read [Autoroller](AUTOROLLER.md) before using it during character creation.

## Support

**SUPPORT** provides:

- **Feedback & Requests** for a detailed suggestion or feature request; and
- **Send Last Debug Report** for the newest privacy-safe diagnostic created after a DGHUD failure.

These submissions do not require a GitHub account or browser. See [Support, Privacy, and Saved Files](SUPPORT_PRIVACY_AND_FILES.md).

## Resizing and responsive behavior

DGHUD recalculates panel sizes, font-aware spacing, chat wrapping, list scrollbars, map height, and resource bars when the Mudlet window changes size. Main game-console wrapping also follows the window while **AUTO MAIN WRAP** is on.

In Mudlet MultiView, these sizes use the individual profile pane, not the entire application window. On narrow panes, Combat stacks its fields so OR, DR, position, and posture remain visible. Inventory, Runes, and Skills start at the top of their scrollable space; long names and columns remain available through horizontal scrolling.

In a very short window, Inventory keeps room for readable item rows. If the money and carry summary cannot fit below the list, it moves inside the list: scroll to the bottom to see it. It returns to its fixed position when you make the window taller.

At wide and medium widths, the side panels use roughly 17 percent of the window each, with a small gap beside the main display. On shorter or narrower desktop windows, **Inventory**, **Runes**, and **Skills** become three tabs sharing the available space; no list is discarded. At compact widths the side rails hide, but those same three scrollable tabs move into a compact strip above the chatbox. On an exceptionally short window, normal game output takes priority and the optional strip returns automatically when enough height is available.

If something disappears after resizing:

1. Enlarge the window slightly.
2. Try **HUD TEXT: Small**.
3. Run `dghud reload` once.
4. If the problem remains, send a report through **OPTIONS → SUPPORT**.

For a layout problem, also enter `dghud layout` and include its privacy-safe output. It reports the chosen breakpoint, window and panel measurements, list mode, font sizes, wrap width, and short view compatibility ID without exposing character or game content.

Hidden optional panels have not been erased. They return when enough space is available.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
