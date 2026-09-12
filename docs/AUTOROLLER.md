# DGHUD Autoroller Guide

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

The DGHUD autoroller watches the current Dragons Gate Character Creator, scores each complete set of 11 characteristics, and sends one `reroll` when the set does not meet your saved rules.

The autoroller never sends `done`. When it finds a result to keep, the creator prompt remains waiting for you.

## Important safety rules

- Use the roller only on the characteristic-rolling step of character creation.
- Set a maximum-roll limit when testing new rules.
- Do not run another standalone Dragons Gate roller at the same time.
- You may type `rr stop` at any time.
- Entering a normal player command while automatic rolling is active cancels the queued automatic action.
- Always inspect the final characteristics and profession fit before entering `done` yourself.

## Current characteristics and score

The current creator has exactly 11 characteristics:

```text
STR INT WIS DEX AGI CON CHA WIL VOI PER APP
```

Each characteristic is worth 1 through 7 points:

| Displayed label | Score |
| --- | ---: |
| Awful | 1 |
| Poor | 2 |
| Low | 3 |
| Aver or Average | 4 |
| Fair | 5 |
| Good | 6 |
| Great | 7 |
| Excel | 7 |
| Superb | 7 |

`Excel` and `Superb` are accepted as top-rank aliases and score the same as `Great`. The maximum total is therefore 77.

MP was removed from the current creator and is not part of the 77-point score. DGHUD can recognize an older 12-value screen only so an outdated or partially updated display does not confuse capture; current settings and limits use 11 characteristics.

## The two current rolling methods

Dragons Gate may let you choose between two workflows. DGHUD supports both.

### Roll in place

The game displays each characteristic in its final position over two rows, followed by:

```text
reroll  done  ? help
```

DGHUD adds all 11 ranks. A normal qualifying roll must reach the target total and satisfy enabled per-characteristic minimums when **Require minimums to stop** is on.

If it does not qualify, DGHUD sends one `reroll`. If it qualifies, DGHUD stops and leaves the prompt waiting for your manual `done` or manual reroll.

### Roll and arrange

The game provides a pool of 11 labels that you can place into characteristics. DGHUD scores the pool before placement.

Choose what should happen to a qualifying pool at the top of **OPTIONS → AUTOROLLER**:

- **LET ME PLACE** — DGHUD stops and leaves all values for you. When enabled, it also verifies that your configured minimums can be satisfied by the pool.
- **GAME AUTO** — DGHUD sends `auto` and waits for the game to finish placing the pool. Per-characteristic minimums cannot promise final positions in this mode, so qualification uses total and optional pool-count rules.
- **MY MINIMUMS + AUTO** — DGHUD places the configured minimum characteristics first, then sends `auto` for values that remain.

For automatic placement, DGHUD confirms every placement message, the matching reduction in the pool, and the next exact creator prompt before sending another command. If confirmation is incomplete, it stops and leaves the prompt for you instead of guessing.

Racial and profession adjustments may change the final labels shown after raw pool values are placed. Minimums in **MY MINIMUMS + AUTO** apply to the raw pool labels available to DGHUD, not to a guaranteed post-modifier final sheet.

## Quick start from the settings box

1. Reach the characteristic-rolling screen.
2. Click **OPTIONS → AUTOROLLER**.
3. Choose the arranged-pool mode you want.
4. Set a **Target total**.
5. Set a **Maximum rolls** value while testing.
6. Enable or disable characteristic minimums.
7. If minimums are enabled, set each characteristic to `1`–`7` or `off`.
8. Review the hard stop carefully.
9. Click **SAVE**.
10. Click **START ROLLER**, or close the panel and enter `rr start`.

With auto-start enabled, DGHUD can begin when it recognizes the exact current rolling screen. `rr start` is the clearest way to resume after you manually stopped or interrupted it.

## Every setting explained

### Target total

The normal minimum total a roll must reach. Valid values are 1 through 77, or `off`.

A target is not the only rule. Enabled minimums and arranged-pool counts may still reject a roll that reaches the target.

Default: `53`.

### Hard stop

An emergency score threshold. A roll at or above this total qualifies immediately before normal minimum and pool-count filters are considered.

Use this when you would rather keep an unusually high total even if its distribution is not ideal. If **MY MINIMUMS + AUTO** cannot actually place the configured minimums, DGHUD still leaves the pool untouched instead of sending an impossible sequence.

Default: `62`.

Set it to `off` if you never want total alone to bypass normal filters.

### Maximum rolls

Stops the session after this many complete rolls. `off` means unlimited.

This is the best safety control while experimenting with strict settings. Reaching the limit does not accept the current roll and does not send `done`.

Default: `off`.

### Reroll delay

Seconds DGHUD waits before sending the next `reroll` after a rejected set.

Default: `0.1` seconds.

Raise this slightly if the connection is lagging or the game is producing incomplete-looking redraws. A delay around `0.2` to `0.5` is easier on a slow connection.

### Minimum Great values

For Roll-and-arrange pools only. Requires at least this many top-rank values. `Great`, `Excel`, and `Superb` all count as top-rank values. Use `off` to disable it.

### Minimum Good-or-Great values

For Roll-and-arrange pools only. Requires at least this many values ranked Good or higher. Top-rank values also count toward this number. Use `off` to disable it.

Example: a pool with two Great values and four Good values has two Greats and six Good-or-Great values.

### Characteristic minimums

Each of the 11 characteristic fields accepts:

- `1` Awful
- `2` Poor
- `3` Low
- `4` Aver
- `5` Fair
- `6` Good
- `7` Great or another top-rank label
- `off` for no minimum on that characteristic

These apply directly to Roll-in-place results. For Roll-and-arrange, they are used by **LET ME PLACE** to test whether the pool is capable of satisfying them, and by **MY MINIMUMS + AUTO** to make the placements.

### Auto-start when roll screen appears

When on, DGHUD begins only after it recognizes a complete supported roll and its exact decision prompt. When off, use `rr start`.

### Enable stat minimums

Master switch for all per-characteristic minimum fields. Turning it off leaves saved numbers available but ignores them.

### Require minimums to stop

For Roll in place and manual arranged placement, this determines whether the enabled minimums are required before a normal target can stop the roller.

In **MY MINIMUMS + AUTO**, the pool must still support the requested placement plan.

### Print every roll

When on, DGHUD prints its score line for every captured roll. Turn it off for a quieter main display; session statistics and logs can still retain useful results.

### Enable roll logging

Writes a timestamped session log and a continuing master log. See [Roll logs](#roll-logs) below.

### Log folder and master filename

These are names inside DGHUD's profile data directory. They may contain letters, numbers, underscores, periods, and hyphens, but not a path.

Defaults:

```text
og_dg_roller
og_dg_rolls_master.txt
```

## Settings that work together

Qualification follows this order:

1. If **Maximum rolls** has been reached, stop safely at the visible prompt.
2. If **Hard stop** is enabled and reached, keep the roll.
3. Otherwise, require **Target total**.
4. Apply relevant per-characteristic or pool rules.

This means a hard stop of 62 can keep a 62-point roll even when one normal minimum is missed. Turn hard stop off when distribution rules must never be bypassed.

The maximum-roll check happens first. If the final roll at the cap would otherwise qualify, DGHUD still reports that the cap was reached and leaves the visible prompt untouched. Set the cap above the amount you truly intend to search.

## Suggested setups

These are starting points, not promises of a particular profession fit.

### Learn the roller safely

- Target total: `50`
- Hard stop: `off`
- Maximum rolls: `100`
- Minimums: off
- Reroll delay: `0.2`
- Arrange mode: **LET ME PLACE**

This is easy to observe and always leaves placement to you.

### Balanced Roll in place

- Target total: `55`
- Hard stop: `62`
- Maximum rolls: `5000`
- Enable minimums.
- Start important characteristics at Fair (`5`) and less important ones at Low (`3`) or `off`.

Requiring Fair in all 11 positions means the minimum possible matching total is already 55. Combining that with an even higher target can make rolls rare.

### Hunt for a strong arranged pool

- Target total: `55`
- Minimum Great values: `2`
- Minimum Good-or-Great values: `5`
- Maximum rolls: `10000`
- Arrange mode: **LET ME PLACE**

Adjust the counts gradually. Requiring many Great values and a high total at the same time can take a very long time.

### Place a few priorities, then auto-fill

- Arrange mode: **MY MINIMUMS + AUTO**
- Enable minimums.
- Set only the most important characteristics, such as two or three values.
- Set every non-priority field to `off`.
- Use a maximum-roll limit.

DGHUD assigns the strictest requested minimum first. Equal minimums follow the normal characteristic order. It assigns the strongest available qualifying pool value to each request.

## Commands

### Session controls

```text
rr start
rr stop
rr stats
rr last
rr reset
rr help
```

- `rr start` starts a new observed rolling session.
- `rr stop` cancels queued rolling and suppresses automatic action until you explicitly restart.
- `rr stats` shows roll count, average, best, and worst.
- `rr last` shows the newest captured roll.
- `rr reset` clears the current session statistics and state. It does not erase old log files.
- `rr help` prints the short command summary.

### Numeric settings

```text
rr set total 55
rr set hard 62
rr set max 5000
rr set delay 0.2
rr set greats 2
rr set goodplus 5
```

Use `off` to disable an optional target, hard stop, maximum, or pool-count setting:

```text
rr set hard off
rr set max off
rr set greats off
rr set goodplus off
```

At least one of target total, hard stop, or maximum rolls must remain enabled.

### Arrange modes

```text
rr set arrange manual
rr set arrange auto
rr set arrange minimums
```

`auto` is saved internally as the game-auto mode.

### Per-characteristic minimums

```text
rr set STR 5
rr set INT 7
rr set WIL 6
rr set APP off
```

Use the settings panel when you want to change many minimums or toggle the master minimum controls.

## Understanding roller output

Roll in place:

```text
[DGHUD Roller] Roll #24  Total=56/77  STR 5  INT 6 ... APP 4
```

Roll and arrange:

```text
[DGHUD Roller] Roll #24  Total=56/77  Pool: Great Good Good Fair ...
```

`TARGET HIT` means DGHUD has stopped sending rerolls. It does not mean the character was accepted. Inspect the game screen and enter `done` yourself only when satisfied.

## Tips and tricks

- Start broad, then tighten one rule at a time. This makes it obvious which setting makes a search too rare.
- Use `rr stats` to judge whether a target is realistic for the rolls you are seeing.
- A high total does not guarantee the values are in useful positions.
- In arranged mode, use Good-or-Great counts when you care about overall pool quality and characteristic minimums when you care about exact placements.
- Keep **LET ME PLACE** selected while testing new arranged-pool settings.
- Use **Print every roll** when diagnosing capture; turn it off for long unattended-looking sessions.
- Increase the reroll delay when connected through a slow or unstable network.
- If you manually enter `reroll`, DGHUD observes that one game command and re-arms capture. It does not intentionally send a second copy.
- If you type another creator or game command, DGHUD yields control and stops automatic sequencing.
- Keep the final `done` decision manual. It is the simplest protection against accepting the wrong character.

## Roll logs

With logging enabled, DGHUD writes:

- one `session_YYYY-MM-DD_HH-MM-SS.txt` file for the current run; and
- one continuing master file.

Default location:

```text
<Mudlet home>/DGHUDData/og_dg_roller/
```

Logs contain timestamped roller status and score lines. Resetting the session or updating DGHUD does not erase old logs.

## Troubleshooting

### It says “Already running”

The roller is active even if it is waiting for the next exact screen. Use:

```text
rr stop
rr start
```

### It does not send another reroll

Check these points:

1. The complete 11-characteristic set appeared.
2. The exact `reroll  done  ? help` or arrangement prompt appeared.
3. `rr stats` shows that DGHUD captured the roll.
4. Maximum rolls was not reached.
5. DGHUD did not print `TARGET HIT`.
6. No normal command canceled automatic rolling.

Then use `rr start`. If the issue continues, update DGHUD and send the exact creator output through Support.

### It stops after only a few rolls

Look for one of these messages:

- target or hard stop reached;
- maximum rolls reached;
- player command canceled rolling;
- placement could not be confirmed;
- configured total cannot be reached; or
- standalone roller conflict.

`rr stats` and `rr last` show what DGHUD most recently captured.

### One typed reroll produces two rerolls

Only one roller should be active. Disable or uninstall the older standalone `og-dg-roller` package. DGHUD refuses to start when it can detect that package, but an unrelated personal trigger can also send another command.

### Settings are impossible or extremely rare

- Every characteristic minimum applies at the same time.
- Good-or-Great includes Great values; it is not an additional separate set.
- Eleven Fair minimums already require at least 55 points.
- Eleven Good minimums require at least 66 points.
- Eleven Great minimums require the perfect total of 77.

Add a maximum-roll limit, lower one requirement, and test again.

### The roller reports a standalone conflict

Open Mudlet's Packages/Scripts tools and disable or uninstall the old standalone roller. Keep only DGHUD's built-in roller active.

### The creator wording changed

DGHUD intentionally waits for exact safe prompts. Copy the full new output, including headings and the final prompt, and send it through **OPTIONS → SUPPORT → FEEDBACK & REQUESTS**.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
