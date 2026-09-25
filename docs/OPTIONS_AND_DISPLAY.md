# DGHUD Options and Display Settings

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

The **OPTIONS** button is at the far left of the header. The current DGHUD version is shown beside it. Click **OPTIONS** to open a short menu of sections.

## Chat Settings

Open **OPTIONS → CHAT SETTINGS → SHOW CHATBOX** to show or completely hide the top-center chatbox. It starts **ON**. Turning it **OFF** expands the main display without deleting history or stopping chat capture. You can reopen Chat Settings through OPTIONS even while chat is hidden. This preference survives character changes, restarts, and HUD updates.

The same window controls which sources appear in ALL, provides separate history-clearing buttons, and offers per-tab sound alerts. Under **SOUND ALERTS**, choose each tab's sound, turn it on or off, or click **PREVIEW**. Staff alerts start on; the other tabs start off. See the [Chatbox Guide](CHATBOX.md).

## Keybindings

Open **OPTIONS → KEYBINDINGS** to enable or customize the number pad. Standard movement follows the keypad compass: 8 north, 9 northeast, 6 east, 3 southeast, 2 south, 1 southwest, 4 west, and 7 northwest. Numpad 5 sends `look`, `+` sends `up`, and `-` sends `down`. The remaining keypad keys are editable and begin blank.

Keep Num Lock on. DGHUD creates temporary bindings that it owns and removes only those exact bindings when it reloads. If a requested key is already assigned in Mudlet, DGHUD leaves its whole keypad set inactive and reports the collision instead of replacing a personal key. Saved choices are stored outside the package and survive updates.

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

## Align command input

Turn **OPTIONS → ALIGN INPUT: ON** to line up the command input's **left edge** with the main game display. It follows the window as you resize it. The input ends before Mudlet's native Search and status controls, which stay visible together on the right. Search remains on the right; this does not align the input to the full width of the main display. The default is **OFF**, and your choice survives updates and restarts independently of automatic word wrap.

This keeps Mudlet's native input, command history, current draft, and aliases. Turn the option **OFF** to restore the prior input stylesheet and compact-input preference, including the previous visibility of Search and status controls. Requires Mudlet 5.0 or newer.

## Color Settings

**COLOR SETTINGS** opens individual toggles for room titles, exits, currency, races, professions, travel objects, combat warnings, recovery, spell threats, discoveries, and illumination.

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

At wide and medium widths, the side panels use roughly 17 percent of the window each, with a small gap beside the main display. On shorter or narrower desktop windows, **Inventory**, **Runes**, and **Skills** become three tabs sharing the available space; no list is discarded. At compact widths the side rails hide, but those same three scrollable tabs move into a compact strip above the chatbox. On an exceptionally short window, normal game output takes priority and the optional strip returns automatically when enough height is available.

If something disappears after resizing:

1. Enlarge the window slightly.
2. Try **HUD TEXT: Small**.
3. Run `dghud reload` once.
4. If the problem remains, send a report through **OPTIONS → SUPPORT**.

For a layout problem, also enter `dghud layout` and include its privacy-safe output. It reports the chosen breakpoint, window and panel measurements, list mode, font sizes, wrap width, and short view compatibility ID without exposing character or game content.

Hidden optional panels have not been erased. They return when enough space is available.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
