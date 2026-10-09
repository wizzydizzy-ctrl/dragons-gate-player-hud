# DGHUD Automapper and Map Library Guide

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

Applies to DGHUD v0.3.96. To check for an update without installing it, enter:

```text
dghud check
```

If a newer release exists, run `dghud update`. For an existing map problem, use the specific steps below rather than reinstalling the HUD.

## Using the automapper

The automapper works automatically while you explore. Move normally and the HUD saves each room using its unique Dragons Gate room number.

It understands:

- `n`, `ne`, `e`, `se`, `s`, `sw`, `w`, and `nw`
- `up`, `down`, `in`, and `out`
- Commands such as `swim north`
- Doors, gates, portals, arches, paths, and other special travel commands
- Named or abbreviated objects: `go store`, `go pawnshop`, `go tav`, `go hole`, and `go exit`

Revisiting a room updates the existing mapped room instead of creating a duplicate.

Special travel stays on the current map by default. A newly discovered destination is placed beside the room you left; the mapper prefers continuing in your direction of travel, avoids ordinary exits and occupied coordinates, and then chooses the next deterministic adjacent space. Existing rooms keep their saved coordinates. If a travel type should begin a separate submap, enable it under **Options → Map Settings**. Gates, portals, doors, arches, paths, and other special travel can each be enabled independently. The return connection is learned after you travel back through it.

### What the connecting lines mean

- **Solid lines:** ordinary directional exits, such as north or southwest.
- **Dotted teal lines:** a saved connection that needs a command such as `go door` or `go portal`. The exact command is saved for automatic walking; it is not replaced with a compass direction.
- A dotted line does **not** promise a return trip. Travel back normally to teach the mapper the return command.

Existing saved special connections receive dotted lines when their current area is activated. A room that was never connected cannot be repaired by guessing from its position: revisit it through its entrance, then use its exit to teach both routes. There is no need to clear the map.

The HUD leaves hand-drawn custom lines and existing room positions alone. If you edit or delete one of its dotted lines, it respects that choice. After manually moving rooms, use the **Center button** to refresh any unchanged HUD-generated dotted connections. Different areas or levels keep their saved travel links, but do not get a misleading line drawn across the current floor.

For very large areas, decorative line generation is limited to 1,000 rooms and 4,096 special exits per area. This safety limit does not remove rooms or travel connections.

## Map controls

The controls above and below the embedded map are:

- **−** — Zoom out.
- **Center button** — Recenter on your current room.
- **+** — Zoom in.
- **Compass buttons** — Move in an available direction.
- **MAP SETTINGS** — Open all mapper controls.
- **Click a known room** — Automatically walk to it.

You can also enter:

```text
walkto 176
```

Replace `176` with a known mapped room number.

```text
walkstop
```

Stops an automatic walk.

```text
mapcenter
```

Centers the map on your current room.

```text
dghud mapstatus
```

Shows the mapper's current room, walking status, and latest error.

## Naming areas and subareas

Stand inside the map you want to name, then open **OPTIONS → MAP SETTINGS**.

1. Enter the main area name, such as `Spur`.
2. Click **NAME CURRENT AREA**.
3. Enter the smaller subarea name, such as `Town Square`.
4. Click **NAME CURRENT SUBAREA**.
5. Click **SAVE**.

The mapper should then display:

```text
Spur - Town Square
```

Names are friendly labels only. The game's permanent room numbers remain unchanged.

If you manually move a mapped room to another area in Mudlet, newly discovered rooms reached from it follow that room's **current area**. You do not need to clear or restart the mapper. Rooms already mapped elsewhere keep their existing area and position. An explicitly enabled separate-submap option still applies to newly discovered special-travel destinations.

## Special-travel settings

Map Settings lets you decide whether each travel type creates a separate submap:

- Gates
- Portals
- Doors
- Arches
- Paths
- Other special travel

All six settings default to **OFF**. Turn a setting **ON** only when that travel type should lead to a separate map.

Changing this setting affects newly discovered destinations. It does not move rooms that were already mapped.

You can also adjust map height, map height percentage, zoom limits, zoom step, autowalk timeout, special-travel detection timeout, and whether automapping is enabled.

Turning automapping off hides or pauses the mapper without deleting saved maps:

```text
dghud mapper off
dghud mapper on
dghud mapper status
```

## Using the Map Library

Open **OPTIONS → MAP SETTINGS → MAP LIBRARY**, or enter:

```text
dghud map library
```

The library has two sections: **MY MAPS** and **SHARED LIBRARY**.

### My Maps

This section contains the map collections saved in your Mudlet profile.

Select a map and choose:

- **USE** — Switch to that map collection.
- **RENAME** — Give it a clearer name.
- **DUPLICATE & EDIT** — Create an editable copy without changing the original.
- **BACKUP** — Create a dated backup collection in **MY MAPS**. Selecting an inactive map for backup switches to that map first.
- **SHARE SELECTED MAP** — Submit it to the community library.
- **DELETE** — Delete that saved collection. You must switch away from an active map first.

Use the name field near the top before choosing **RENAME** or **DUPLICATE & EDIT**.

For a portable local JSON export of HUD-owned rooms in the active map, enter `dghud map export my_backup local-export`, then `dghud map folder` to open its folder. Exporting does not submit anything for review. Copy important backups outside the profile for protection against losing the profile itself.

### Finding community maps

Open **SHARED LIBRARY**, then click **FIND SHARED MAPS**.

You can search by map name, area name, subarea name, or creator. You can also filter the results by **ALL**, **FULL MAPS**, **AREAS**, or **SUBAREAS**.

Select a result before choosing a download action.

### Download as New — recommended

**DOWNLOAD AS NEW** creates and activates a separate editable map collection. Your previous collection is saved, and you can switch back under **MY MAPS**.

### Add to Current Map

**ADD TO CURRENT MAP** creates a new combined editable collection containing your current map and the downloaded map. Your original collections remain available.

If the same room number exists in both maps, choose:

- **CURRENT MAP WINS** — Keep your version of overlapping rooms.
- **DOWNLOADED MAP WINS** — Use the downloaded version.
- **SKIP COLLISIONS** — Do not import overlapping areas.
- **CREATE COMBINED MAP** — Finish creating the new collection.

Room numbers are permanent game identifiers, so review collision choices carefully.

### Replace Current

**REPLACE CURRENT** replaces the active map with the downloaded map. DGHUD creates a backup first and requires a second warning click. Use this only when you intentionally want to replace everything in the active collection.

### Update My Copy

**UPDATE MY COPY** downloads the newest library version of a map you previously downloaded. Select the same shared map entry first. Be careful if you have made personal changes to your copy.

DGHUD finds a matching downloaded collection, switches to it if needed, creates a dated backup, and replaces that copy with a fresh download. Personal additions are preserved in the backup, not merged into the refreshed copy.

### Importing a local backup

Enter `dghud map folder` to open the transfer folder. Place a DGHUD JSON export there using a simple filename such as `my_backup.json`, then enter:

```text
dghud map import my_backup
```

Read the preview. For overlaps, choose **KEEP MY MAP**, **USE SHARED MAP**, or **SKIP THIS AREA**, then **FINISH INSTALLING**. These labels are also used for local-file imports. **USE SHARED MAP** can replace overlapping HUD-owned rooms; unrelated personal rooms are protected. This import updates the active map rather than creating a separate collection, so back it up first. Enter `dghud map import cancel` to cancel the preview.

## Editing downloaded maps

Downloaded maps are editable. To protect your work:

1. Select the map under **MY MAPS**.
2. Choose **DUPLICATE & EDIT**.
3. The copy becomes active automatically. Use **RENAME** if you did not enter a name before duplicating.
4. Continue exploring and making additions.

Your changes never alter the original creator's uploaded map.

## Sharing a map

Under **MY MAPS**:

1. Select the map you want to share.
2. Click **SHARE SELECTED MAP**.
3. Wait for the upload result and keep its submission reference.

No GitHub account is required. Clicking **SHARE SELECTED MAP** starts the upload directly; there is no separate name-and-creator form. DGHUD uses the current character name supplied by the game as creator credit, or `Unknown` if unavailable. Map data and that credit are submitted for owner review before public publication. Review the selected collection and your current character before clicking Share.

If you downloaded someone else's map, improved it, and want to share your version:

1. Use your editable copy.
2. Find its original entry under **SHARED LIBRARY**.
3. Select it.
4. Click **UPLOAD MY VERSION**.

Your upload becomes your own submitted version. It does not overwrite the original creator's map.

## Fixing a bad map

Before deleting map data, stop any active walk:

```text
walkstop
```

Open **MAP SETTINGS** and use:

- **DELETE CURRENT MAP** — Remove only the map or submap containing your current room.
- **WARNING: CLEAR ALL MAPS** — Remove every DGHUD-owned map and start fresh.

Cleanup uses a two-step confirmation. Read the preview, wait at least one second when clearing everything, and click the confirmation button again within 30 seconds.

DGHUD only deletes rooms it can verify belong to the HUD. It will not intentionally delete unrelated personal Mudlet maps.

Advanced cleanup commands include:

```text
dghud map delete room 176
dghud map clear current
dghud map clear submap 900
dghud map clear area Dragons Gate - Training Grounds
dghud map clear all
dghud map cancel
```

## Reporting a mapper problem

If mapping, downloading, uploading, or cleanup fails:

1. Open **MAP SETTINGS → MAP LIBRARY**.
2. Click **REPORT A PROBLEM**.
3. Wait for the report result and keep its reference. Clicking the button sends the newest sanitized failure report directly.

No GitHub account is required, and chat logs or passwords are not included.

You can also enter:

```text
dghud map debug
```

This sends a sanitized mapper report and gives you a reference number.

For a local mapper report without uploading it, enter `dghud map debug folder`. DGHUD saves the diagnostic and opens its folder.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
