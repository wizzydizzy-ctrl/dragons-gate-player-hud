# DGHUD Color Highlighting Guide

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

DGHUD can highlight selected game output while leaving ordinary room prose and chat unchanged. Highlights change color only; they do not hide or rewrite the words.

All highlight categories are enabled by default. Open **OPTIONS → COLOR SETTINGS** to switch them individually.

## Available categories

| Setting | What it highlights | Default appearance |
| --- | --- | --- |
| All Highlights | Master switch for DGHUD output coloring. | On |
| Room Titles | Bracketed room-name lines. | Bronze/gold |
| Exits / Directions | `Obvious exits:` or `Obvious paths:` labels and their directions. | Dark red and dark orange |
| Currency | `gold`, `silver`, `gp`, and `sp` in applicable display output. | Gold and silver |
| Races | Known race names wherever the race matcher applies. | Race palette |
| Classes | Known profession names wherever the class matcher applies. | Profession palette |
| Travel Objects | Door, gate, arch, portal, stairs, ladder, trapdoor, bridge, tunnel, passage, entrance, or exit phrases in travel-object lines. | Cyan |
| Attacks on You | Recognized attacks aimed at you. | Red |
| Damage to You | `Your ... takes ... points of ... damage!` | Bright red |
| Danger / Blocks | Blocked movement and recognized hard warnings. | Amber |
| Recovery | Fully rested and fully healed messages. | Muted green |
| Ongoing Costs | Recognized fatigue upkeep messages. | Dim orange |
| Spell Threats | Recognized room-wide or incoming casts. | Purple |
| Discovery / Loot | Recognized discovery messages. | Gold |
| Illuminated Areas | Both illuminated and not-illuminated room status. | Yellow for illuminated; blue-gray for dark |

## Using the settings box

1. Click **OPTIONS**.
2. Click **COLOR SETTINGS**.
3. Click a category to switch it on or off.
4. Close the panel when finished.

Selections are saved and survive `dghud reload` and package updates.

The **MAPPER** control in the same settings panel shows or hides mapping without deleting map data.

## Command-line controls

Master control:

```text
dghud colors on
dghud colors off
dghud colors toggle
dghud colors status
```

Individual control:

```text
dghud colors room toggle
dghud colors exits off
dghud colors currency on
dghud colors illumination status
```

Valid feature names are:

```text
room exits currency races classes highlights portal attack damage danger recovery upkeep spell discovery illumination
```

The `highlights` feature groups travel objects, attacks, damage, danger, recovery, costs, spells, discovery, and illumination. Race, profession, room-title, exit, and currency switches remain independently controllable.

## What to expect

Examples:

```text
[Old Cemetery.]
Obvious paths: north east west.
This area is illuminated.
This area is not illuminated.
An open sinister black iron gate is here.
The dark hound claws at you!
Your head takes 8 points of impact damage!
You cannot move in that direction.
```

DGHUD matches the game text itself, including ANSI-colored input. If a new wording does not highlight, send the exact full game line through **OPTIONS → SUPPORT → FEEDBACK & REQUESTS**. A screenshot helps, but the exact copied line is more useful for building a safe matcher.

## Why some similar lines remain uncolored

The matchers are deliberately restrained:

- A random NPC sentence containing `says` is not treated as a combat alert.
- Every sentence ending with `is here` is not treated as a travel object.
- Attacks on another character are not highlighted as attacks on you.
- Ordinary uses of words such as `full`, `rested`, or `satisfied` do not become recovery notices.

This reduces false positives and keeps normal prose readable.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
