# DGHUD Screen and Character Data

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

Applies to DGHUD v0.3.90.

DGHUD combines live GMCP information with complete responses to ordinary Dragons Gate commands. GMCP is preferred when the same value is available from both sources.

## Header

The header contains:

- the **OPTIONS** button;
- the installed DGHUD version;
- **DRAGONS GATE**;
- STR, INT, WIS, DEX, AGI, CON, CHA, WIL, PRE, PER, and LUK;
- your computer's local real time; and
- synchronized Dragons Gate time with **Daytime** or **Night**.

Game time is synchronized from `time` output and advances locally at the configured two-times rate. DGHUD labels 6:00 AM through 5:59 PM as Daytime and 6:00 PM through 5:59 AM as Night.

Enter `time` whenever you want to resynchronize it.

## Main display and command input

In **OPTIONS**, **ALIGN INPUT: OFF** appears immediately after **AUTO MAIN WRAP**. Its tooltip describes **Align input with main display (left edge only)**. Input alignment is optional and off by default; click the row to turn it on or off. When on, Mudlet's main command input follows the main display's left edge as the window is resized. The input ends before the native Search and status controls, which stay visible together on the right. Search remains on the right; the input is not aligned to the full width of the main display.

Your normal native command input remains available with the same draft, command history, and alias behavior. Turning alignment **OFF** restores the previous input stylesheet and compact-input preference, so the Search and status controls return to their previous visibility. Your alignment choice survives updates and restarts.

Input alignment is independent of **AUTO MAIN WRAP**, which controls line wrapping in the main display.

On shorter windows, Inventory, Runes, and Skills share a tabbed area on the right. Click **INVENTORY**, **RUNES**, or **SKILLS** to see the corresponding list; narrower layouts shorten these labels to **INV**, **RUN**, and **SKL**. If there is too little height even for the tabs, enlarge the window. See [Options and Display](OPTIONS_AND_DISPLAY.md) for text-size presets and responsive layout controls.

## Identity

The Identity section may show:

- full name;
- race and profession;
- a dragon's stage in place of a missing profession;
- age, sex, and height;
- deity, devotion level, and favor count together, such as **Unknown · Novitiate · 57,000**;
- religious balance and alignment; and
- Food and Water status.

Alignment wording is made more readable in the HUD: order becomes **Orderly**, entropy becomes **Entropic**, and chaos becomes **Chaotic**.

Food and Water begin unknown. A complete character INFO description updates both: any reported hunger or thirst status is shown, while a missing status shows **Ok** in green. This works whenever that description appears in game output, including wrapped lines, not just during the startup command sequence.

`You are satiated.` shows **Food: Satiated**, and `Your thirst is quenched.` shows **Water: Quenched**, both in green. Later hunger or thirst messages replace the corresponding status independently. A lone hunger notice does not reset Water, and eating or drinking alone does not prove either status is healthy. Incomplete INFO responses do not clear previous warnings.

Identity and characteristics come from GMCP plus `info` and `info religion`.

## Equipment readiness

The Equipment section intentionally shows only:

- weapon ready or not ready; and
- shield ready or not ready.

These are current GMCP readiness flags. Item names printed by `stat` are not used as the equipment display.

Equipment is optional at shorter window heights and may hide before more important panels do.

## Location and navigation

The Location section uses GMCP Room information:

- room name and permanent room number;
- game area number;
- terrain or environment;
- number of players in the room;
- room flags; and
- available exits.

The compass makes available directions brighter and unavailable directions subdued. The small travel buttons send `go portal`, `go door`, `go gate`, or `go arch` exactly as labeled.

The embedded map and map collection name appear above the compass. See [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md).

## Combat

The Combat section can show:

- armor percentage;
- stance and OR on the same row;
- roundtime and DR on the same row;
- tactical area position; and
- standing, sitting, or unconscious state when known.

OR, DR, armor, stance, and tactical position come from `stat`. Recognized combat fields are retained as they arrive, even if another command interrupts the response. Confirmed attack-strategy messages also update stance immediately. Posture begins unknown and changes only after recognized game messages.

The separate roundtime bar below the mapper controls remains empty at READY. Separate printed delay messages accumulate, including double attacks and fumble penalties. GMCP roundtime is a snapshot, not another delay to add: matching snapshots are reconciled with recent output, and unchanged cached values do not restart the countdown. Fresh changed snapshots can correct the remaining time. The local countdown accounts for elapsed time if Mudlet is busy. Because the game does not supply a delay/event ID, near-simultaneous text and GMCP are correlated within a short window rather than claiming perfectly identifiable events.

After printed delays, DGHUD requests a quiet `delay` check once the output burst settles, no more than once every three seconds. `You have 12 second(s) remaining!` replaces the countdown with 12; it does not add 12 more seconds. Only a reply confirmed to belong to DGHUD's own check is hidden. Your manually entered `delay` results remain visible and also synchronize the bar. If manual and automatic checks overlap, or reply ownership is uncertain, the text stays visible. Requests pause after a timeout or failure and are not sent during character-data refreshes, autorolling, or updates. This is an occasional correction, not continuous polling.

## Inventory, money, and carrying capacity

Inventory shows every captured item in a scrollable list. Long names and large inventories use horizontal and vertical scrollbars rather than shrinking the text indefinitely.

Below the list, DGHUD shows:

- gold as `gp` in gold coloring;
- silver as `sp` in silver coloring; and
- carry current / maximum / percentage.

Items and total carried weight come from `inventory`. Money comes from GMCP Vitals; the Carry figures use GMCP Vitals when available, with INFO values as a fallback. In a short tabbed Inventory panel, money and Carry may appear inside the scrollable list; scroll below the items to find them.

## Runes

`info magic` fills the Runes list. DGHUD retains every elemental rune and sorts the list by the fewest weaves remaining first, then by name. The list scrolls when it is longer than the visible space.

This puts the runes closest to needing renewal at the top.

## Skills

`skill` fills the Skills list. **OPTIONS → Skill Settings** gives **Main Display** and **Right Sidebar** independent sorting choices. Each has a primary key, ascending or descending order, and an optional secondary key with its own direction. Available keys are **Level**, **Uses**, **Name**, **Number**, **Ready to train (0 uses)**, and **Category (combat vs utility)**. Both displays default to **Level descending**, then **Uses ascending**; choose **Level** primary and **Uses** secondary for “level then uses.”

Sidebar sorting changes immediately reorder existing rows. Main sorting changes apply to the next complete `skill` output and leave previously printed tables as they are. Choices are saved for the whole profile and survive character changes, reloads, restarts, and HUD updates. Category and Ready to train sorting keep every captured skill visible.

The sidebar shortens names for readability, such as `Identify` becoming `ID`, while the captured skill record remains available to the HUD. The formatted main table shortens weapon names to `Sharps`, `Blunts`, `Poles`, `Throws`, and `Missiles`. Columns stay aligned, and scrollbars appear when needed.

The **MAIN SKILLS** toggle in **Skill Settings** is on by default. It formats complete `skill` responses in the main game console using the **Main Display** order, for example:

```text
Number  Skill   LVL  USES
     2  Sharps    4   400
    46  Biting    4   414
```

The leading catalog number is the game's fixed training skill ID, not a display rank. Sharp Weapons stays `2` regardless of its level or where it sorts. Every skill in your response is included; skills you do not possess are not added. Future unrecognized skill names show `?` rather than an invented number. Turning **MAIN SKILLS** off keeps future responses in the game's original layout. This toggle does not change the sidebar's layout, send training commands, or replace unrelated game output.

To narrow one response in the main display, enter `skill <prefix>`, for example `skill claw`, `skill bite`, `skill c`, `skill id`, or `skill ste`. Matching ignores case and checks the start of the name, including supported shortened names; the text is not a wildcard or pattern. Enter `skill` or `skill all` to show the full list again. Each request fetches the full table, so the Skills sidebar retains all your skills even when the main response is filtered.

`skill weapons` shows only your possessed Sharp, Blunt, Pole, Throw, and Missile Weapons and natural attacks: Biting, Clawing, Webbing, Breath Weapon, and Stinging. The group uses catalog IDs 2–6, 46–49, and 57. It does not include Identify Weapon Quality, Weapon Smithing, or every combat skill. A filter with no matches prints `No skills match: <prefix>`.

Filters also work with **MAIN SKILLS** off, keeping the game's row format and order. If another refresh or skill request is loading, wait for it to finish and try again. Filtering finishes when the complete table ends, without needing Enter. DGHUD redraws removed rows locally so they do not leave a blank gap at the bottom, and preserves your position when reading scrollback. A filter applies to one response only; canceled or expired requests do not carry their filter into the next request.

Use these exact group filters: `skill combat` shows blue combat rows with uses left, and `skill utility` shows yellow utility rows with uses left. `skill train` shows every green zero-use row, whether combat or utility; it only displays the list and never sends a game training command. Group names ignore case and still work if you customize or disable the colors. `skill weapons` and name-prefix filters still include matching zero-use skills, and the sidebar always retains the full list.

Whole rows with **0 uses remaining are green**, combat skills are **blue**, and utility skills are **yellow**. The green ready-to-train color takes priority. Combat includes weapons, Focus Force, Biting, Clawing, First Aid, and other combat abilities; Identify skills, Swimming, Riding, and other utility skills stay yellow unless they have zero uses. Change or disable these styles under **OPTIONS → COLOR SETTINGS → TEXT STYLES → Skills**. These choices are saved with your profile.

## Resource bars

The bars immediately above Mudlet's command line show:

- Health;
- Fatigue;
- PSI when a positive maximum is known, or your profession is Psion or Psycian;
- Web when a positive maximum is known, or your race is Arachnian; and
- both PSI and Web when both apply.

The bars divide the main-display width according to how many are visible and may use two rows in compact layouts. Profession- or race-based bars can appear before their values arrive. Health, Fatigue, PSI, and Web prefer GMCP Vitals, with INFO values as a fallback. Carry is shown under Inventory instead of taking a resource bar.

## Refreshing information

Run the complete safe refresh with:

```text
dghud refresh
```

Or run one source command manually:

```text
inventory
stat
info
info religion
info magic
skill
time
```

DGHUD normally waits for a complete response and its prompt before replacing a captured list. Skills also recognize the game's table-ending blank lines, so a completed list updates on the next UI tick without waiting for another command or injecting an Enter. A header or a pause between rows does not finish the table. Combat fields update as soon as recognized.

## Data that updates immediately through GMCP

The currently used structured data includes:

- `Char.Status`: name, surname, race, class, and alignment;
- `Char.Vitals`: health, fatigue, PSI, Web, carry, money, position, roundtime, weapon readiness, and shield readiness;
- `Room.Info`: room number, name, area, environment, exits, and flags;
- `Room.Players`; and
- `Room.WrongDir`.

Fields not supplied through GMCP are filled from the command responses listed above.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
