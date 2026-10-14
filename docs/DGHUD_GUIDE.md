# Complete DGHUD Guide

Applies to DGHUD **v0.3.104**. Older screenshots and messages may use different labels.

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

To install a newer release, run `dghud update`. If it reports that you are already current, nothing is reinstalled. Use `dghud refresh` for stale character information instead.

## What's new in v0.3.104

- **LINK is the standard combined tab** for mental/ESP/contact and Dragon, Psycian, and Secian link messages. No setting needs to be enabled.
- Existing profiles upgrade automatically. History, original message channels, per-source sounds, Show in ALL choices, and outgoing capture preferences are preserved.
- Drag LINK into the position you prefer. Custom categories named LINK or LINK VIEW remain separate and cannot hide the built-in tab.

See [the LINK tab](CHATBOX.md#the-link-tab).

## Previous changes in v0.3.103

- Outgoing CONTACT requests are saved locally in MENTAL after a confirmed character session. They are labeled as requests, not proof of delivery; matching own broadcast echoes are not duplicated.
- **OPTIONS → CHAT SETTINGS** can turn outgoing capture off or combine the mental/racial link tabs into one **LINK** view. Separate tabs remain the default. History, original channels, sound choices, and Show in ALL rules stay intact.
- **Visibility: Hidden / Visible / Unknown** appears under Food and Water, based on confirmed self messages and your own INFO. Old confirmations are marked stale; failed hide attempts and other characters' INFO do not change your status.
- Turn the visibility row off with **OPTIONS → HIDDEN / VISIBLE**. These features add no periodic INFO or SPELLS requests.

See [Chatbox](CHATBOX.md#outgoing-contact-messages) and [Visibility](HUD_SCREEN_AND_CHARACTER_DATA.md#hidden-visible-and-unknown). Effects and Tactical views remain pending representative output and a defined source.

## Previous changes in v0.3.102

- **MENTAL** combines ESP, contact thoughts, and generic mental links.
- Explicit **Psycian links** now have a dedicated **PSYCIAN** tab. Named **DRAGON** and **SECIAN** links keep their own tabs.
- Older saved messages are shown in the correct tabs without changing their text. Tab order and saved Show in ALL and sound choices migrate automatically.
- MENTAL and PSYCIAN can each be included in ALL or given their own sound under **OPTIONS → CHAT SETTINGS**.

See [Chatbox filters and migration](CHATBOX.md#built-in-filters) for details.

## Previous changes in v0.3.101

- Autoroller Presence and Luck minimums now stay **OFF**, even when older Voice or Appearance targets were saved.
- Numeric targets and old command names stay compatible; saving, reopening, and restarting no longer bring an old target back.
- Use `off`, not `1`, to leave a characteristic out of your minimums and automatic minimum placement.

See [characteristic minimums](AUTOROLLER.md#characteristic-minimums) for the difference between OFF and rank 1.

## Previous changes in v0.3.100

- `shoprenewall` now accepts the full normal magic output, including modifier and shape lists.
- The Runes list and Lua values refresh as soon as the elemental table ends. Renewal commands still wait for the completed response.
- Chat mentioning runes is ignored as data, and conflicting or incomplete lists cannot trigger renewals.
- Rune displays retry failed redraws and stay visible when the layout changes.
- `trainall` still trains only known skills with **0 uses**. Disable any older personal `trainall` alias if it also runs; your personal aliases are not removed.

See [renewal and training commands](COMMAND_REFERENCE.md#rune-renewal-and-training-shortcuts) for setup and stopping rules.

## Previous changes in v0.3.99

- Runes use aligned **Runes / Weaves Remain** columns, with all counts in a right-aligned numeric column.
- `shoprenew` checks fresh runes and renews those below 20 weaves; `shoprenewall` renews every captured rune.
- `trainall` checks fresh skills and raises known skills with 0 uses by their game IDs.
- Each shortcut sends one command per second. Independent saved ON/OFF switches are under **OPTIONS → Skills & Runes**. Use `shoprenewstop` or `trainallstop` to cancel.
- Rune variables refresh cleanly, the name box no longer shows the balance/alignment row, and staff referrals are captured even when wrapped.

See [renewal and training commands](COMMAND_REFERENCE.md#rune-renewal-and-training-shortcuts) before using the resource-spending shortcuts.

## Previous changes in v0.3.98

- In the normal combined layout, **Inventory** and the combined **Skills / Runes** card now have the same height and width, evenly splitting the available space below content-sized **Combat** across window sizes and Mudlet MultiView panes.
- Existing fonts, aligned columns, sorting, tab choices, and horizontal/vertical scrollbars are unchanged. **COMBINED SKILLS / RUNES OFF** keeps the separate-box sizing unchanged.
- When the window is too short for both cards to fit complete rows, tabs, and the Inventory footer safely, the existing three-way Inventory / Runes / Skills compact/tabbed fallback continues without forcing tiny fonts or clipping.
- Very short panes now give complete rows and horizontal scrollbars priority over duplicate headings and inner whitespace. Inventory totals move into the scrollable list when they cannot fit below it.
- Food and Water now recognize explicit recovery and stop messages, including **Full** and **Sloshing**. Sloshing is a stop-drinking warning. See the [six exact status transitions](HUD_SCREEN_AND_CHARACTER_DATA.md#identity).
- Wrapped, confirmed complete INFO still reports **Satiated** / **Quenched**, or **Ok** for an omitted status. Eating/drinking, burps, “not bad,” and “hit the spot” alone never infer status.

See [Right sidebar](HUD_SCREEN_AND_CHARACTER_DATA.md#right-sidebar) and [Combined Skills / Runes](OPTIONS_AND_DISPLAY.md#combined-skills--runes), or read the [release notes](https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/tag/v0.3.98).

## Previous changes in v0.3.97

- **OPTIONS → COMBINED SKILLS / RUNES** defaults to **ON**, with a taller tabbed card below the separate Inventory card and its existing **Equipped** / **Carried** tabs. Combat stays at the top, sized to its contents.
- **Skills** is selected initially. The layout choice and selected **Skills** / **Runes** tab are saved per profile through updates, restarts, and character changes.
- Both lists update behind the tabs; switching tabs displays saved data and sends no extra game commands.
- Existing fonts, sorting, colors, aligned columns, and horizontal/vertical scrollbars are preserved.
- Turn the option **OFF** for separate Runes and Skills boxes. The existing three-way Inventory / Runes / Skills compact tabs remain a fallback for short or narrow windows.

See [Right sidebar](HUD_SCREEN_AND_CHARACTER_DATA.md#right-sidebar) and [Combined Skills / Runes](OPTIONS_AND_DISPLAY.md#combined-skills--runes), or read the [release notes](https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/tag/v0.3.97).

## Previous changes in v0.3.96

- Choose a personal WAV or a built-in **Three-Tone**, **Chime**, **Alarm**, or **Horn** for a qualifying autoroller result.
- Open **OPTIONS → Autoroller**, then scroll to **ALERTS** in the same settings window. Use **CHOOSE WAV FILE…**, **PREVIEW**, **STOP PREVIEW**, and volume **1–100**, then click **SAVE**.
- Completion sounds default to **ON**, **Three-Tone**, volume **75**; repeating alerts default to **OFF**. Optional reminders repeat about every ten seconds, wait for longer sounds between plays, and stop after five minutes.
- A persistent **AUTOROLLER TARGET HIT** notice appears even with sound off. **DISMISS / SILENCE** acknowledges the alert without accepting or discarding the result; final acceptance stays manual.
- Automatic placement must be confirmed before a success alert. Errors, disconnects, and the maximum-roll limit are not reported as successful rolls.
- Validated custom WAVs and saved alert preferences remain private with the Mudlet profile and survive restarts, character changes, and updates. New rolling sessions, character exit, and HUD shutdown clear old reminders rather than carrying them into another character.

Custom files must be normal PCM or IEEE-float WAVs, at most **10 MiB** and **60 seconds**. Mudlet's media mute and your computer's volume still apply. See [completion sounds and reminders](AUTOROLLER.md#completion-sounds-and-reminders) for setup and troubleshooting, or read the [release notes](https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/tag/v0.3.96).

## Previous changes in v0.3.95

- Fixed a Windows color-settings save failure that prevented category buttons and text styles from saving.
- Skill results no longer inherit an unintended red background or other formatting from previous highlighted output.
- Turning **SKILL ROW COLORS** off keeps the aligned table in plain gray on the normal main-display background.
- Saved skill color choices survive restarts and updates; intentional custom background highlights remain supported.
- Added clearer [plain gray skill instructions](COLOR_HIGHLIGHTING.md#prefer-plain-gray-skill-text) without weakening file-safety checks.

[Read the release notes](https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/tag/v0.3.95).

## Previous changes in v0.3.94

- Inventory now has **Equipped** and **Carried** tabs. Each keeps its own saved list, so switching is immediate and does not send another game command.
- Current unnumbered inventory rows and nested locations such as **legs (pants)** are captured correctly. Duplicates remain separate.
- Gold, silver, and Carry remain your character's totals on either tab. Small windows retain scrollable items and totals without shrinking the font.
- **Water: Dehydrated** is shown as a red warning. Inventory refreshes no longer lift the tabs over an open settings window.
- Long rune names expand the scrollable list so the full name and weave count remain visible in narrow windows.

See [Inventory, money, and carrying capacity](HUD_SCREEN_AND_CHARACTER_DATA.md#inventory-money-and-carrying-capacity) for the new tabs, or read the [release notes](https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/tag/v0.3.94).

With **SKILL FILTERS ON**, filtering remains independent of custom or disabled colors and works with MAIN SKILLS off, preserving the game's row format and order. Main-display and sidebar sorting remain independent.

## Complete guide index

| Guide | What it explains |
| --- | --- |
| [Installation and First Start](INSTALLATION_AND_FIRST_START.md) | Requirements, installation, first login, and what DGHUD does automatically. |
| [HUD Screen and Character Data](HUD_SCREEN_AND_CHARACTER_DATA.md) | Every visible section, where its information comes from, and how to refresh it. |
| [Options and Display Settings](OPTIONS_AND_DISPLAY.md) | Every button under **OPTIONS**, text size, resizing, and saved preferences. |
| [Chatbox](CHATBOX.md) | Tabs, Show in ALL, hiding chat, sound alerts, profile-wide history, and custom capture triggers. |
| [Color Highlighting](COLOR_HIGHLIGHTING.md) | Built-in highlights, color choices, and how to add your own words or phrases. |
| [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md) | Automatic mapping, special submaps, walking, cleanup, named map collections, sharing, downloading, and combining maps. |
| [Autoroller](AUTOROLLER.md) | Both rolling methods, targets, session highs, custom completion sounds, reminders, commands, and troubleshooting. |
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
- **Information side:** In the normal [combined layout](HUD_SCREEN_AND_CHARACTER_DATA.md#right-sidebar), content-sized Combat sits above Inventory and the combined Skills / Runes card. The two list cards have the same height and width and evenly split the available space below Combat across window sizes and MultiView panes. Inventory keeps Equipped / Carried tabs; Skills is selected initially in the lower card. Both lists update in the background; switching tabs sends no command. Existing fonts, sorting, colors, columns, tab choices, and both scrollbars remain.

**OPTIONS → COMBINED SKILLS / RUNES** defaults to ON; OFF restores separate boxes. The preference and selected Skills / Runes tab persist per profile through updates, restarts, and character changes.

DGHUD responds to window resizing and each MultiView pane. If both equal-sized cards cannot safely fit complete rows, tabs, and the Inventory footer at a short height, the existing three-way Inventory / Runes / Skills compact/tabbed fallback continues without forcing tiny fonts or clipping. Narrow windows retain their existing compact behavior. At smaller sizes, optional sections may hide so the game display and command line remain usable. This does not erase their data.

## What happens after character login

After Dragons Gate prints the character welcome message, DGHUD gathers information once, in sequence:

```text
inventory
stat
info
info religion
info magic
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

Saved choices belong to the Mudlet profile, not the individual character. A different profile has its own preferences, chat history, and map collections.

## Getting help quickly

Open **OPTIONS → HELP & COMMANDS** or enter:

```text
dghud help
```

For a problem that the normal fixes do not solve, open **OPTIONS → SUPPORT**. You can send feedback or a privacy-safe diagnostic without a GitHub account.

[Back to the repository](../README.md)
