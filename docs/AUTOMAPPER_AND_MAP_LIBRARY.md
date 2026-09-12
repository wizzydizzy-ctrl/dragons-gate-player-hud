# DGHUD Automapper and Map Library Guide

Make sure you are using DGHUD v0.3.32 or newer:

```text
dghud update
```

## Using the automapper

The automapper works automatically while you explore. Move normally and the HUD saves each room using its unique Dragons Gate room number.

It understands:

- `n`, `ne`, `e`, `se`, `s`, `sw`, `w`, and `nw`
- `up`, `down`, `in`, and `out`
- Commands such as `swim north`
- Doors, gates, portals, arches, paths, and other special travel commands

Revisiting a room updates the existing mapped room instead of creating a duplicate.

Special travel normally creates a separate submap so doors, gates, and portals do not distort the regular area map. The return connection is learned after you travel back through it.

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

## Special-travel settings

Map Settings lets you decide whether each travel type creates a separate submap:

- Gates
- Portals
- Doors
- Arches
- Paths
- Other special travel

Leave a setting **ON** when that travel type should lead to a separate map. Turn it **OFF** when it should continue drawing on the current map.

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
- **BACKUP** — Save a private local backup.
- **SHARE SELECTED MAP** — Submit it to the community library.
- **DELETE** — Delete that saved collection. You must switch away from an active map first.

Use the name field near the top before choosing **RENAME** or **DUPLICATE & EDIT**.

### Finding community maps

Open **SHARED LIBRARY**, then click **FIND SHARED MAPS**.

You can search by map name, area name, subarea name, or creator. You can also filter the results by **ALL**, **FULL MAPS**, **AREAS**, or **SUBAREAS**.

Select a result before choosing a download action.

### Download as New — recommended

**DOWNLOAD AS NEW** creates a separate editable map collection. Your current map remains unchanged, and you can switch between them under **MY MAPS**.

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

## Editing downloaded maps

Downloaded maps are editable. To protect your work:

1. Select the map under **MY MAPS**.
2. Choose **DUPLICATE & EDIT**.
3. Give your copy a new name.
4. Select **USE**.
5. Continue exploring and making additions.

Your changes never alter the original creator's uploaded map.

## Sharing a map

Under **MY MAPS**:

1. Select the map you want to share.
2. Click **SHARE SELECTED MAP**.
3. Complete the requested name and creator information.
4. Submit it.

No GitHub account is required. Shared maps are submitted for safety review before they appear publicly, so they may not appear in the library immediately.

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
3. Submit the privacy-safe diagnostic.

No GitHub account is required, and chat logs or passwords are not included.

You can also enter:

```text
dghud map debug
```

This sends a sanitized mapper report and gives you a reference number.
