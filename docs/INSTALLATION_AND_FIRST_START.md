# DGHUD Installation and First Start

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

## What you need

- Mudlet 5.0.0 or newer.
- A Dragons Gate Mudlet profile.
- An internet connection for the first download and future update checks.

Install DGHUD only from the official release link shown below. A Mudlet package contains Lua code that runs inside the active profile, so do not substitute an unfamiliar repository address.

## Fresh installation

1. Open the Dragons Gate profile where you want to use DGHUD.
2. Click Mudlet's normal command line.
3. Paste this entire line and press Enter:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/latest/download/DragonsGateHUD.mpackage")
```

4. Allow Mudlet a few moments to register and start the package.
5. If the HUD does not appear, close and reopen that profile once.
6. Log into a character.

The installation affects only the profile in which you run the command.

## What should appear

When the HUD starts successfully, you should see:

- a **DRAGONS GATE** header;
- an **OPTIONS** button and version number;
- a chatbox above the normal game display;
- identity and navigation information on one side;
- combat and character lists on the other side; and
- resource bars directly above Mudlet's command line.

The exact arrangement changes with window width and height. A very narrow window uses a compact layout and hides nonessential side content.

## First character login

DGHUD waits until you enter a character. It does not run character commands at the account or character-selection menu.

After a character welcome line, it gathers the information that Dragons Gate does not currently send through GMCP. You may briefly see these commands:

```text
inventory
stat
info
info religion
info mag
skill
time
```

They run one at a time so the responses do not become mixed together. DGHUD uses the results to fill inventory, combat, identity, religion, runes, skills, needs, characteristics, and game time.

## If a section remains blank

Wait until the startup sequence has finished, then enter:

```text
dghud refresh
```

This refreshes character data only. It does not download, uninstall, or reinstall DGHUD.

You can also enter one source command manually. For example:

```text
skill
info mag
inventory
```

DGHUD captures a complete manual response and updates the matching panel.

## Existing installations from 0.3.15 or older

Very old versions kept personal HUD data inside the replaceable package directory. Install the migration bridge once before updating one of those versions:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/latest/download/DGHUDMigration.mpackage")
```

The bridge copies and verifies personal settings, chat history, map collections, exports, and diagnostics in the profile's separate `DGHUDData` directory. Current versions already use that directory.

## Recommended first settings

Open **OPTIONS** and check these items:

- Leave **Automatic Updates** off until you decide you want login-time updates.
- Choose **HUD Text: Small, Normal, or Large** for your screen.
- Open **Color Settings** and disable any highlight you do not want.
- Open **Map Settings** and decide which special travel types should begin submaps.
- Read the [Autoroller Guide](AUTOROLLER.md) before starting automatic rolling.

## Verify the installation

Enter:

```text
dghud check
```

DGHUD prints the installed version and whether it is current. A check does not install anything.

If the normal HUD is missing but the recovery companion is present, enter:

```text
dghud recover
```

See [Updates and Emergency Recovery](UPDATES_AND_RECOVERY.md) before using recovery.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
