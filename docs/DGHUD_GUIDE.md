# Complete DGHUD Guide

DGHUD is a Mudlet HUD for Dragons Gate. It organizes important character information, communication, navigation, and utility tools around the normal game display. It does not replace Dragons Gate commands, and it does not require you to edit Lua scripts for ordinary use.

This page is the main guide. Use the links below to open a detailed guide for each part of the HUD.

## Start here

If DGHUD is not installed yet, follow [Installation and First Start](INSTALLATION_AND_FIRST_START.md).

If DGHUD is already installed, the three most useful commands are:

```text
dghud help
dghud refresh
dghud check
```

- `dghud help` opens the built-in command guide.
- `dghud refresh` refreshes character information without reinstalling anything.
- `dghud check` checks whether a newer release exists without installing it.

## Complete guide index

| Guide | What it explains |
| --- | --- |
| [Installation and First Start](INSTALLATION_AND_FIRST_START.md) | Requirements, installation, first login, and what DGHUD does automatically. |
| [HUD Screen and Character Data](HUD_SCREEN_AND_CHARACTER_DATA.md) | Every visible section, where its information comes from, and how to refresh it. |
| [Options and Display Settings](OPTIONS_AND_DISPLAY.md) | Every button under **OPTIONS**, text size, resizing, and saved preferences. |
| [Chatbox](CHATBOX.md) | Chat categories, filters, permanent local history, and custom capture triggers. |
| [Color Highlighting](COLOR_HIGHLIGHTING.md) | Every optional highlight, what each color means, and how to toggle it. |
| [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md) | Automatic mapping, special submaps, walking, cleanup, named map collections, sharing, downloading, and combining maps. |
| [Autoroller](AUTOROLLER.md) | Both character-creation rolling methods, every setting, recommended setups, commands, and troubleshooting. |
| [Updates and Emergency Recovery](UPDATES_AND_RECOVERY.md) | Safe manual updates, optional automatic updates, preserved data, and `dghud recover`. |
| [Command Reference](COMMAND_REFERENCE.md) | One searchable list of every normal DGHUD and autoroller command. |
| [Troubleshooting](TROUBLESHOOTING.md) | Fast fixes for missing panels, stale data, mapper problems, update failures, and roller problems. |
| [Support, Privacy, and Saved Files](SUPPORT_PRIVACY_AND_FILES.md) | Feedback, anonymous diagnostics, what stays local, and where DGHUD stores its files. |

## A quick tour of the screen

- **Header:** DGHUD version, all 11 characteristics, real time, and synchronized game time.
- **Top-center chatbox:** Saved communication with category filters.
- **Center:** The normal Dragons Gate game display.
- **Bottom-center:** Resource bars without covering the command line.
- **Identity and navigation side:** Name, race, profession or dragon stage, physical details, faith, favors, alignment, hunger, thirst, equipment readiness, location, mapper, compass, travel buttons, and the roundtime bar.
- **Information side:** Combat, inventory and money, runes, and skills. Lists gain scrollbars when their contents do not fit.

DGHUD responds to window resizing. At smaller sizes, optional sections may hide so the game display and command line remain usable. This does not erase their data.

## What happens after character login

After Dragons Gate prints the character welcome message, DGHUD gathers information once, in sequence:

```text
inventory
stat
info
info religion
info mag
skill
time
```

The game may not provide all of this through GMCP, so DGHUD combines structured GMCP data with these command responses. It also captures the same commands when you enter them manually. Use `dghud refresh` to run the complete sequence again.

## Safe-use rules

- Use `dghud check` when you only want to check for an update.
- Automatic updating is off by default. Turning it on is optional, and your choice survives updates.
- DGHUD never sends `done` during character rolling. You make the final choice.
- Stop automatic walking with `walkstop` before cleaning or replacing a map.
- Read map cleanup and replacement previews before confirming them.
- Do not include passwords, private account information, or private conversations in feedback forms.
- DGHUD owns its own package resources and data. It is designed not to edit personal triggers, aliases, scripts, keys, packages, or unrelated maps.

## Getting help quickly

Open **OPTIONS → HELP & COMMANDS** or enter:

```text
dghud help
```

For a problem that the normal fixes do not solve, open **OPTIONS → SUPPORT**. You can send feedback or a privacy-safe diagnostic without a GitHub account.

[Back to the repository](../README.md)
