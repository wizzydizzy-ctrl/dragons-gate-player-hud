# DGHUD Troubleshooting

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

Start with the smallest action that matches the problem. A data refresh is safer and faster than a package update, and a reload is safer than removing a package.

## Quick decision guide

| Problem | First action |
| --- | --- |
| One character panel is stale or empty | `dghud refresh` |
| Layout looks wrong after resizing | `dghud reload` |
| Unsure whether an update exists | `dghud check` |
| A newer release exists | `dghud update` |
| Main HUD is missing or unhealthy | `dghud recover` |
| Map is wrong | `walkstop`, then open Map Settings |
| A feature failed and created a report | Options → Support → Send Last Debug Report |

## The entire HUD is missing

1. Make sure the affected Mudlet profile is active.
2. Close and reopen that profile once.
3. Enter:

```text
dghud recover
```

If Mudlet says that command is unknown, install the independent recovery companion:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/latest/download/DGHUDRecovery.mpackage")
```

Then run `dghud recover` again.

Do not delete the profile or `DGHUDData` folder as a first response. They contain saved settings, chat, and map collections.

## The HUD is visible but one panel is blank

Enter:

```text
dghud refresh
```

Wait for all seven source commands to complete. If only one section is blank, run its command manually:

- Inventory: `inventory`
- Combat: `stat`
- Identity, needs, vitals fallback, and characteristics: `info`
- Faith and favors: `info religion`
- Runes: `info mag`
- Skills: `skill`
- Game clock: `time`

DGHUD keeps the previous valid value when a response is incomplete. A panel may therefore remain unchanged until the game prints a complete response and prompt.

## Skills, inventory, or runes do not scroll

- Put the mouse over the list itself, not its title or surrounding card.
- Use the vertical bar on the right for more rows.
- Use the horizontal bar at the bottom for long names or hidden columns.
- Try **OPTIONS → HUD TEXT: Small** if the window is narrow.
- Enlarge the Mudlet window enough to leave the right rail visible.

The lists retain all parsed rows even when only part of the list fits.

## Text wraps differently after resizing

DGHUD calculates wrap columns from the actual main-display and chatbox pixel widths. Run:

```text
dghud reload
```

If the main console still appears unusually narrow or wide, resize the window by a small amount to fire Mudlet's resize event. Send a support report with Mudlet version, operating system, resolution, and window size if it remains wrong.

## A panel disappears in a small window

This can be normal responsive behavior. Optional Equipment hides before essential content, and all side rails hide in compact mode.

Try:

1. **HUD TEXT: Small**;
2. a slightly taller or wider window; and
3. `dghud reload`.

The panel data is not deleted.

## The character refresh seems delayed

The commands run sequentially. DGHUD waits for a complete prompt so one response does not contaminate the next. Skills and inventory can take longer because their output may contain many lines.

If the game prompt does not arrive, DGHUD sends one blank prompt nudge and uses bounded recovery timeouts before continuing. Do not repeatedly send the same refresh commands while the startup sequence is active.

## Roundtime is stuck

DGHUD takes the newest confirmed value from GMCP or a delay line and counts down once per second. A later Vitals event can correct it.

If it remains stuck:

1. perform an action that creates a new delay;
2. wait for a new game prompt;
3. run `dghud refresh`; and
4. send a report if the number still does not change.

## Standing or sitting is missing

Posture begins unknown. DGHUD does not assume that a character starts standing.

Use a normal posture command and wait for a confirmed game message such as:

```text
You stand up.
You sit down.
You lie down.
```

Lying, falling unconscious, or passing out is represented under the sitting/not-standing state. General lines such as `You are thrown off balance!` do not change posture.

## Game time is wrong

Enter:

```text
time
```

DGHUD resynchronizes from the line beginning `It is now ...`. Real Time comes from the computer's local clock and timezone.

## Colors do not appear

Check the current states:

```text
dghud colors status
```

Turn on the master and relevant feature:

```text
dghud colors on
dghud colors illumination on
```

Color matching uses specific safe wording. If a new game line remains uncolored, submit the exact copied line, not only a paraphrase.

## Map movement creates an isolated room or wrong submap

1. Stop any route with `walkstop`.
2. Run `dghud mapstatus` and note the latest error.
3. Check **Map Settings** special-travel toggles.
4. Remember that changing a special-travel toggle affects newly discovered transitions; it does not relocate rooms already saved.
5. Delete only the affected current map or room when possible instead of clearing everything.

See [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md).

## Map cleanup refuses to run

DGHUD blocks cleanup when it cannot prove ownership, current-room state, inbound exits, or movement safety.

- Stop automatic walking.
- Wait for any movement or special transition to finish.
- Make a fresh preview.
- Confirm within 30 seconds.
- Do not try to reuse an old token.

There is no force option. Submit a mapper diagnostic if the ownership or safety error persists.

## A shared map does not appear immediately

Sharing submits a map for validation and owner review. Submission success is not the same as publication. The map appears in the public catalog only after it is approved and the catalog is rebuilt.

Use **FIND SHARED MAPS** again after approval. Search by map name or creator.

## Update says the installed version is current

This is expected:

```text
[DGHUD] Version ... is already up to date.
```

The updater correctly skipped reinstalling the same version. Use `dghud refresh` when you wanted to refresh character panels.

## Update download times out

- Check that normal internet access is working.
- Wait a minute before trying again.
- Use `dghud check` first.
- Do not start overlapping update attempts.
- Keep automatic updates off if the connection is unreliable.

If the running HUD remains healthy, continue playing and send the generated diagnostic later.

## An update reports a health-check or activation failure

The updater should retain or restore the prior working HUD when the newly registered package does not become healthy.

1. Wait for Mudlet to finish saving.
2. Close and reopen the profile if the interface is unresponsive.
3. Run `dghud recover`.
4. Send the last debug report after recovery.

## The autoroller does not continue

Use:

```text
rr stats
rr last
```

Then review the [Autoroller troubleshooting section](AUTOROLLER.md#troubleshooting). The most common causes are a reached target, maximum-roll cap, player command cancellation, unrecognized creator prompt, or a second roller conflict.

## A normal command behaves differently with DGHUD

DGHUD creates aliases only for documented `dghud ...`, `rr ...`, `walkto`, `walkstop`, and `mapcenter` commands. It does not intentionally create broad aliases for unrelated game commands.

If a command such as `lay hands` works only with different capitalization, inspect personal Mudlet aliases and triggers first. Disable them one at a time in an isolated profile before attributing the behavior to DGHUD.

## Send a useful report

Open **OPTIONS → SUPPORT** and submit the newest privacy-safe report. In a feedback description, include:

- what you expected;
- what happened;
- the exact command you entered;
- the exact DGHUD error line;
- Mudlet version and operating system;
- window resolution or size for a layout problem; and
- repeatable steps.

Never include a password or other account secret.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
