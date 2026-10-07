# DGHUD Troubleshooting

Applies to DGHUD **v0.3.92**.

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
- Runes: `info magic`
- Skills: `skill`
- Game clock: `time`

DGHUD keeps the previous valid value when a response is incomplete. A panel may therefore remain unchanged until the game prints a complete response and prompt.

Skills are an exception: a complete skill table ending in blank lines is saved on the next UI tick, without waiting for another prompt. Commands still depend on the game sending the response; DGHUD cannot show fresh results before they arrive.

## Filtered skills leave a blank gap or seem stuck

1. Run `dghud check` and update if your installed version is older than **0.3.89**.
2. Wait for the current startup/refresh sequence or skill request to finish, then enter `skill bite`, `skill weapons`, or another filter once.
3. Use `skill` or `skill all` for the complete list again. The sidebar always keeps every captured skill.
4. If a gap remains on v0.3.92, send a report with the command, filter and formatting toggles, whether you were reading scrollback, and a screenshot of the window.

The fix refreshes hidden-row edits locally. You should not need to send Enter or another game command just to make the blank area disappear.

## Skills, inventory, or runes do not scroll

- Put the mouse over the list itself, not its title or surrounding card.
- Use the vertical bar on the right for more rows.
- Use the horizontal bar at the bottom for long names or hidden columns.
- Try **OPTIONS → HUD TEXT: Small** if the window is narrow.
- On a compact window, use the **INV**, **RUN**, and **SKL** tabs above the chatbox. If the window is exceptionally short, enlarge it vertically to restore the optional list strip; the game console is kept visible first.

The lists retain all parsed rows even when only part of the list fits.

## Text wraps differently after resizing

DGHUD calculates wrap columns from the actual main-display and chatbox pixel widths while **OPTIONS → AUTO MAIN WRAP** is on. Turn it off if you want Mudlet's profile preference to control the main game window instead. Chatbox wrapping remains responsive either way.

For automatic wrapping, run:

```text
dghud reload
```

If the main console still appears unusually narrow or wide, resize the window by a small amount to fire Mudlet's resize event. Run `dghud layout` and include that safe output with a support report if it remains wrong. Its wrap field reports `automatic` or `manual`.

## A panel disappears in a small window

This can be normal responsive behavior. Optional Equipment hides before essential content, and the side rails hide in compact mode. Inventory, Runes, and Skills remain available as tabs above the chatbox.

Try:

1. **HUD TEXT: Small**;
2. a slightly taller or wider window; and
3. `dghud reload`.

The panel data is not deleted.

## The character refresh seems delayed

The commands run sequentially. DGHUD waits for a complete prompt so one response does not contaminate the next. Skills and inventory can take longer because their output may contain many lines.

For inventory, stat, info, religion, and magic responses, DGHUD may request a blank prompt nudge and uses bounded recovery timeouts before continuing. It does **not** send those extra Enters for `skill` or `time`. A delayed or cancelled request is kept separate from the next one. Do not repeatedly send the same refresh commands while the startup sequence is active.

## Roundtime is stuck

DGHUD counts down locally once per second. Printed action delays can accumulate, including double attacks and fumbles; GMCP snapshots are reconciled to reduce duplicate counting. A repeated unchanged GMCP value does not restart the bar.

After a printed-delay burst, DGHUD can make a throttled `delay` check and use the game's remaining total. Only a proven HUD-requested, isolated response is hidden. Your manually entered `delay` result stays visible; ambiguous overlapping replies stay visible too. Automatic checks pause during startup collection, updates, and autorolling, and suspend after a failed or timed-out check rather than repeatedly polling.

If the bar looks wrong, enter:

```text
delay
```

Compare `You have ... second(s) remaining!` with the bar. The manual response also corrects its countdown. If they still differ, send that exact reply and the preceding action/delay lines through Support. A GMCP dump can contain an older snapshot even while the HUD's local timer counts down normally.

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

DGHUD recognizes the current month-name format, for example `Today is the 59th day of Majus in the year 362. The time is 4:29.`, and the older `It is now ...` format. Real Time comes from the computer's local clock and timezone, not the server's timezone line. Daytime/Night uses the configured game-time boundaries (6 AM and 6 PM by default), not a measured sunrise/sunset event.

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

## Update stopped safely and mentions differing personal-data copies

Stop the autoroller and enter `dghud safe update`. If Mudlet reports an unknown command, install the migration bridge from the [safe-upgrade instructions](UPDATES_AND_RECOVERY.md#update-stopped-safely-run-the-safe-upgrade-bridge). Do not delete the differing files or manually uninstall to get past the check. The bridge preserves conflict copies before retrying the verified update.

## The autoroller does not continue

Use:

```text
rr status
rr show
rr stats
rr last
```

The **Waiting** line from `rr status` explains the immediate pause, and `rr show` verifies all saved settings. Then review the [Autoroller troubleshooting section](AUTOROLLER.md#troubleshooting). The most common causes are a reached target, maximum-roll cap, player command cancellation, unrecognized creator prompt, or a second roller conflict.

## A normal command behaves differently with DGHUD

DGHUD handles the documented `dghud ...`, `rr ...`, walking, and local `skill` filtering commands. With **SKILL FILTERS ON**, skill filters request the normal game table. To send native arguments such as `skill Rath` unchanged, choose **OPTIONS → Skill Settings → SKILL FILTERS OFF → Save**. Bare `skill` still refreshes your complete sidebar; **MAIN SKILLS** controls formatting separately. The filter choice survives reloads and updates. DGHUD does not intentionally create broad aliases for unrelated game commands.

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
