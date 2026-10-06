# DGHUD Color Highlighting Guide

Applies to DGHUD **v0.3.90**.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

DGHUD can highlight selected game output while leaving ordinary room prose unchanged. Travel objects, other listed room objects, and the words `is here` / `are here` have separate styles. Important version notices also receive an “IMPORTANT - PLEASE READ” heading.

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
| Travel Objects | Doors, gates, arches, portals, stairs, ladders, trapdoors, bridges, tunnels, passages, entrances, exits, paths, holes, stores, shops, pawnshops, and taverns in confirmed object listings. | Cyan |
| Other Objects / Here | Non-travel objects in a confirmed room listing, plus separate `is here` / `are here` wording. | Muted green for objects; bright yellow for the presence wording |
| Attacks on You | Recognized attacks aimed at you. | Red |
| Damage to You | `Your ... takes ... points of ... damage!` | Bright red |
| Danger / Blocks | Blocked movement and recognized hard warnings. | Amber |
| Recovery | Fully rested and fully healed messages. | Muted green |
| Ongoing Costs | Recognized fatigue upkeep messages. | Dim orange |
| Spell Threats | Recognized room-wide or incoming casts. | Purple |
| Discovery / Loot | Recognized discovery messages. | Gold |
| Illuminated Areas | Both illuminated and not-illuminated room status. | Yellow for illuminated; blue-gray for dark |
| Important Game Notices | New version-notes announcements. | Gold text, dark red highlight, bold and underline |
| World Arrivals / Departures | Standalone character arrival/departure notices in the main display and WORLD chat. Includes unexpected departures. | Green for arrival; red for departure |
| Skill Row Colors | Full rows in the formatted main-window skill table. | Green for zero uses; otherwise blue for combat or yellow for utility |

## Using the settings box

1. Click **OPTIONS**.
2. Click **COLOR SETTINGS**.
3. In **CATEGORIES**, click a category to switch it on or off. These switches save immediately.
4. In **TEXT STYLES**, choose a group and then the text you want to customize.
5. Choose a color swatch or enter a six-digit hex color such as `#74A9FF`. Press Enter to preview typed colors; nothing is sent to the game.
6. Choose **SWATCHES: TEXT** or **SWATCHES: HIGHLIGHT** to decide which color the swatches change. Turn Highlight on for a colored background, or off for text-only coloring.
7. Set Bold, Underline, and the individual style's On/Off choice.
8. Click **SAVE** to apply. **CANCEL** discards unsaved edits. **RESET** restores the original style in the preview; click Save to keep it.

## Custom words and phrases

Open **OPTIONS → COLOR SETTINGS → CUSTOM WORDS/PHRASES** to add your own highlights. Enter the exact word or phrase you want to find, then choose its text color, optional background highlight, bold, underline, and on/off state. Save it to apply to new game text. Select a saved entry to change it later, or delete it when you no longer want it.

Matches are literal text, not regular expressions, and ignore case for English and common accented Latin letters. Other scripts may need exact capitalization. A saved word is matched as a word rather than inside a longer word. Custom entries apply to new output in the main display and can override an overlapping built-in color without changing the original game text. Important version notices keep their prominent warning even when a custom phrase overlaps them. The master All Highlights switch still controls whether any coloring appears. Custom entries remain private to the Mudlet profile; they are saved with the other color settings and survive HUD updates, character changes, and restarts.

For example, save `secret path` with yellow text and a dark background to make that phrase stand out whenever the game prints it. You can save up to **1,000** custom entries; each phrase is limited to **120 bytes** (some accented characters use more than one byte). Oversized or invalid entries are rejected rather than partly saved.

**Example: change exits to blue.** Open Text Styles, select **Exit directions**, choose blue, then Save. The `Obvious exits:` / `Obvious paths:` label is a separate style, so it can stay red or use another color.

Room titles, exit labels, directions, gold, silver, each known race and profession, travel objects, other room objects, `is here` / `are here`, combat highlights, illumination/darkness, important notices, and the three skill row colors all have separate editable styles. The relevant category and master switches must also be on for a built-in style to appear. Skill row colors require **OPTIONS → Skill Settings → MAIN SKILLS** to be on; switching the colors off leaves its aligned table layout on. Sorting never changes the green priority for rows with 0 uses. World notice colors also apply to their corresponding chat notices; the main-display skill styles do not recolor sidebar rows.

Selections apply to **new output**, not previously printed lines. Use `look` to see a room description again. Saved choices survive HUD reloads, package updates, character changes, and Mudlet restarts within the same profile. They are stored as validated data in `DGHUDData/color-settings.dat`, outside the replaceable package. A failed save shows an error and does not apply partial changes.

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
room exits currency races classes highlights portal presence attack damage danger recovery upkeep spell discovery illumination notice world skills
```

The `highlights` feature groups travel objects, other room objects/presence wording, attacks, damage, danger, recovery, costs, spells, discovery, illumination, version notices, world notices, and skill row colors. Race, profession, room-title, exit, and currency switches remain independently controllable.

## What to expect

Examples:

```text
[Old Cemetery.]
Obvious paths: north east west.
This area is illuminated.
This area is not illuminated.
An open sinister black iron gate is here.
A store, a pawnshop, a tavern, and a fountain are here.
A dark hole and a sputtering smoky torch are
here.
The dark hound claws at you!
Your head takes 8 points of impact damage!
You cannot move in that direction.
```

DGHUD matches the game text itself, including ANSI-colored input. If a new wording does not highlight, send the exact full game line through **OPTIONS → SUPPORT → FEEDBACK & REQUESTS**. A screenshot helps, but the exact copied line is more useful for building a safe matcher.

## Why some similar lines remain uncolored

The matchers are deliberately restrained:

- A random NPC sentence containing `says` is not treated as a combat alert.
- Ending in `is here` alone does not make an object a travel exit. Confirmed object listings are distinguished from quoted speech and unrelated narration.
- In mixed lists, a shop, hole, door, or other recognized travel phrase uses its travel style. Torches, fountains, and other listed objects can use the separate **OTHER OBJECTS / HERE** styles. Disable that category if you only want travel objects colored.
- A confirmed travel-object listing may span up to four server lines. Quoted speech, command echoes, and unrelated prose are not travel listings.
- Attacks on another character are not highlighted as attacks on you.
- Ordinary uses of words such as `full`, `rested`, or `satisfied` do not become recovery notices.

This reduces false positives and keeps normal prose readable.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
