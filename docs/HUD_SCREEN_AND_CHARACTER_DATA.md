# DGHUD Screen and Character Data

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

DGHUD combines live GMCP information with complete responses to ordinary Dragons Gate commands. GMCP is preferred when the same value is available from both sources.

## Header

The header contains:

- the **OPTIONS** button;
- the installed DGHUD version;
- **DRAGONS GATE**;
- STR, INT, WIS, DEX, AGI, CON, CHA, WIL, VOI, PER, and APP;
- your computer's local real time; and
- synchronized Dragons Gate time with **Daytime** or **Night**.

Game time is synchronized from `time` output and advances locally at the configured two-times rate. DGHUD labels 6:00 AM through 5:59 PM as Daytime and 6:00 PM through 5:59 AM as Night.

Enter `time` whenever you want to resynchronize it.

## Identity

The Identity section may show:

- full name;
- race and profession;
- a dragon's stage in place of a missing profession;
- age, sex, and height;
- religious rank and deity;
- favors;
- religious balance and alignment; and
- Food and Water status.

Alignment wording is made more readable in the HUD: order becomes **Orderly**, entropy becomes **Entropic**, and chaos becomes **Chaotic**.

Food and Water begin unknown. DGHUD changes them only after a confirmed status phrase. Eating or drinking an item does not automatically mean the character is full.

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

OR, DR, armor, stance, and tactical position come from `stat`. Roundtime comes from GMCP and confirmed delay output. Posture begins unknown and changes only after recognized game messages.

The separate roundtime bar below the mapper controls remains empty at READY. When a delay begins, it fills and counts down locally while later GMCP updates correct it.

## Inventory, money, and carrying capacity

Inventory shows every captured item in a scrollable list. Long names and large inventories use horizontal and vertical scrollbars rather than shrinking the text indefinitely.

Below the list, DGHUD shows:

- gold as `gp` in gold coloring;
- silver as `sp` in silver coloring; and
- carry current / maximum / percentage.

Items and total carried weight come from `inventory`. Money and carrying capacity prefer GMCP Vitals values.

## Runes

`info mag` fills the Runes list. DGHUD retains every elemental rune and sorts the list by the fewest weaves remaining first, then by name. The list scrolls when it is longer than the visible space.

This puts the runes closest to needing renewal at the top.

## Skills

`skill` fills the Skills list. DGHUD retains every skill and sorts them by:

1. highest level first;
2. lowest remaining uses next; and
3. skill name for an exact tie.

Long display names are shortened only for readability, such as `Identify` becoming `ID`, while the captured skill record remains available to the HUD. Columns stay aligned, and scrollbars appear when needed.

## Resource bars

The bars immediately above Mudlet's command line show:

- Health;
- Fatigue;
- PSI when PSI is applicable and has a maximum;
- Web when Web is applicable and has a maximum; and
- both PSI and Web when both apply.

The bars divide the main-display width evenly according to how many are visible. Carry is shown under Inventory instead of taking a resource bar.

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
info mag
skill
time
```

DGHUD waits for a complete response and its prompt before replacing the previous valid data. This avoids displaying half of a list when the game or network is delayed.

## Data that updates immediately through GMCP

The currently used structured data includes:

- `Char.Status`: name, surname, race, class, and alignment;
- `Char.Vitals`: health, fatigue, PSI, Web, carry, money, position, roundtime, weapon readiness, and shield readiness;
- `Room.Info`: room number, name, area, environment, exits, and flags;
- `Room.Players`; and
- `Room.WrongDir`.

Fields not supplied through GMCP are filled from the command responses listed above.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
