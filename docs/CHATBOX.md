# DGHUD Chatbox Guide

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

Applies to DGHUD v0.3.108.

The chatbox appears above the normal game display by default. It copies recognized communication into a separate readable history without gagging, replacing, or changing the original game line.

To hide it completely, open **OPTIONS → CHAT SETTINGS** and set **SHOW CHATBOX: OFF**. The main game display expands into the freed space. Chat capture and saved history continue while hidden; this does not turn off logging. Return to the same setting and switch it **ON** to see your messages again. Your choice is saved for the profile and survives character changes, restarts, and HUD updates. It does not change your tab order or SHOW IN ALL choices.

Chat history belongs to the Mudlet profile, not to one character. Switching characters in the same profile keeps the same history.

## Resize the chatbox

Open **OPTIONS → CHAT SETTINGS → HEIGHT** near the top of the settings window.

- **COMPACT**, **NORMAL**, and **LARGE** choose responsive height presets.
- **SMALLER −20px** and **LARGER +20px** adjust the requested height in 20-pixel steps.
- You can also drag the narrow bottom edge of the chatbox up or down. Release the mouse button to apply and save the new size; it does not save repeatedly while you drag.
- **RESET SIZE** restores the Normal preset. It does not clear history or change tab order, Show in ALL, sounds, or outgoing capture.

Custom heights are limited to **80–600 pixels**. A short window may show less than the requested height so the main game display remains usable. The height label shows the actual size and, when different, the requested size. Enlarging the window gives the saved request room again. Presets adapt to the profile pane's height instead of promising the same pixel size at every resolution.

Changes save immediately for this Mudlet profile and survive character changes, profile restarts, and HUD updates. A failed save leaves the previous size active. No game command or history reload is needed.

Chat stays full-width above the main display; it is not a freely floating window. Smaller chat frees main-display space, not space in the independent right-side Skills / Runes card. **OPTIONS → HUD TEXT → Small** can fit more sidebar rows without changing the main game font. See [responsive layout](OPTIONS_AND_DISPLAY.md#resizing-and-responsive-behavior).

Use **OPTIONS → CHAT SETTINGS** to clear only the visible chatbox or permanently remove all saved DGHUD chat history. Permanent deletion requires two clicks; the command-line equivalent requires the full `dghud chat clear saved confirm` phrase.

The same settings window has a **SHOW IN ALL** section. Toggle any source to control whether it appears in **ALL**. `COMBAT` starts off there; every other source starts on. Turning a source off only excludes it from ALL: LINK and the other chat views still capture and save its messages. Choices persist through profile restarts and HUD updates.

## Outgoing CONTACT messages

Open **OPTIONS → CHAT SETTINGS → CAPTURE OUTGOING CONTACTS**. It starts **ON** and your saved choice survives updates and restarts. After the HUD confirms a character session, a complete `contact <target> <message>` request appears in **PRIVATE** for a named recipient, or **LINK** for `all` / `room`, retaining MENTAL as its source:

```text
You -> recipient (outgoing request): Hello!
```

This records what you requested, **not proof that the game accepted or delivered it**. The HUD does not resend the command, change it, or hide its normal game output. `contact all`, `contact room`, and named targets are supported when followed by a message. Bare commands, help requests, other commands, login input, and multiline input are not recorded by this feature.

An exact, recent, matching own broadcast echo is not added a second time to the chatbox. Ambiguous echoes and other speakers' messages stay visible. Repeating a request intentionally keeps each request. Outgoing requests and reconciled own echoes do not play chat alerts.

Outgoing entries follow MENTAL's **SHOW IN ALL** choice and save in the same local profile history even while the chatbox is hidden. Named requests stay in PRIVATE; room/global requests stay in LINK. They are not uploaded. Turn the setting **OFF** if you do not want outgoing requests saved; this does not delete existing history.

## The LINK tab

**LINK is the standard tab** for mental/ESP broadcasts, room/global contact thoughts, and Dragon, Psycian, and Secian links. Direct contacts such as `Seaux thinks to you, "Hello"` appear only in PRIVATE, alongside whispers and outgoing named contacts. LINK appears automatically, including when upgrading a profile saved with separate tabs in v0.3.103. There is no separate/combined switch to enable.

Every message retains its original source channel, saved history, and per-source sound settings. **SHOW IN ALL** continues to use the individual source choices, not the combined label. Turning PSYCIAN off there, for example, keeps Psycian messages in LINK but excludes them from ALL. MENTAL controls ALL inclusion for both direct contacts and mental broadcasts; neither PRIVATE nor LINK loses its own messages when that source is excluded from ALL.

LINK initially takes the first constituent tab's position, unless you already saved a combined order. Drag it to your preferred position; that order is remembered. The older source-tab order remains saved for compatibility. Upgrading while viewing a constituent selects LINK; ALL, PRIVATE, STAFF, and personal filters stay selected normally. A profile restart or ordinary reload starts on ALL as before.

Personal categories are not merged: a custom LINK appears as **LINK (custom)** alongside the built-in tab, and a personal LINK VIEW remains its own category. Neither can disable the standard LINK tab or consume another category's messages.

## Sound alerts

Open **OPTIONS → CHAT SETTINGS → SOUND ALERTS**. Each tab has an **ON/OFF** control, a choice of twelve short sounds, and a **PREVIEW** button. Each built-in tab starts with a different sound. **STAFF starts ON; all other alerts start OFF** in a new profile. Existing alert choices migrate during updates. You can change the shared alert volume too. Changes save immediately for this Mudlet profile and survive restarts, character changes, and HUD updates.

Preview lets you hear a sound even when that tab's alerts are OFF; it does not turn the alert on. The sounds are created locally from tones included in the HUD—no external media download or account is required. Mudlet's **Mute all media** and your computer's audio settings still apply.

MENTAL, DRAGON, PSYCIAN, and SECIAN remain independent **source controls** here, not separate visible tabs. MENTAL controls the source sound for both direct contacts in PRIVATE and mental broadcasts in LINK.

Only newly captured messages alert. Loading saved history, scrolling, switching tabs, changing characters, and updating the HUD do not replay old alerts. Rapid messages are limited to one alert per second per selected tab.

A message can appear in ALL and another filter, but plays only one sound: its specific enabled source takes priority, then **PRIVATE** for a direct conversation, then **ALL** if the message is included there. PRIVATE alerts never fire for room/global/racial-link broadcasts. For example, enabling MENTAL and ALL does not make mental messages ding twice. Hiding the chatbox does not mute alerts; turn off its alert switches when you want silence. Custom tabs appear in the sound settings after they are created and start OFF.

## Built-in filters

- **ALL** — Captured categories enabled under **SHOW IN ALL**, plus skill improvements, skill-training readiness, stat increases, and fatigue gains from diligent training.
- **ROOM** — Nearby speech and your own speech.
- **PRIVATE** — Whispers, one-to-one incoming mental contacts (`Name thinks to you, "..."`), and your outgoing CONTACT requests to a named recipient. Nearby speech addressed to someone remains ROOM because it is still public speech.
- **LINK** — ESP, room/global contact thoughts, generic mental links, and named Dragon, Psycian, and Secian links. Outgoing `contact all` and `contact room` requests appear here. Direct contacts do not also appear in LINK. Original source labels and source-specific settings are retained.
- **STAFF** — Recognized Guide, GM, Elder, sends, voice, and referral list, handling, and detail formats.
- **COMBAT** — Your attacks, incoming weapon attacks, hit/miss results, damage, movement blocks, spell threats, upkeep, and recovery. This tab keeps capturing and saving messages even when **SHOW IN ALL → COMBAT** is OFF.
- **WORLD** — Character arrivals (green) and departures (red), including unexpected departures. It starts included in ALL. Turn **SHOW IN ALL → WORLD** OFF to keep these messages only in WORLD; capture and saved history continue. WORLD sound alerts start OFF. Customize the two colors independently in **Color Settings → Text Styles → World arrivals / World departures**.

Drag any chat tab left or right to arrange the filters in the order you prefer. The order is saved for the whole Mudlet profile and survives character changes, reconnects, and HUD updates. A short click still selects the tab normally.

### Older tabs and saved messages

If PRIVATE and LINK both show shared link traffic, check the version beside OPTIONS and run `dghud update` in that profile. Older versions grouped whole link channels into PRIVATE. Complete shared-link frames saved or captured under PRIVATE or WHISPER are now corrected for display and alerts; you do not need to clear chat. Unrecognized intentional custom PRIVATE entries remain available there.

ESP and CONTACT share the MENTAL source. Named Psycian, Dragon, and Secian links keep their matching sources, while generic mental links remain MENTAL. Broadcasts display together in LINK; recognizable direct contacts display in PRIVATE, including older saved messages with the full direct-contact frame. A legacy CONTACT category alone does not prove a message was private. Original saved categories and message text are not rewritten or deleted.

MENTAL remains included in ALL if either previous ESP or CONTACT source was included. PSYCIAN initially inherits the previous ESP inclusion choice. An explicit saved MENTAL or PSYCIAN choice always wins, including OFF.

For alerts, MENTAL retains an enabled ESP sound first, otherwise an enabled CONTACT sound; if both were off, it stays off. PSYCIAN initially inherits the old ESP alert preference. Your explicit new-channel choices always win. The older ESP and CONTACT sound choices remain available in the sound list.

If all tabs do not fit, click the final overflow control to cycle through hidden categories. A filter missing from the visible row may be there. Custom categories added by personal triggers become available as filters too, and can be reordered after they appear. Combat capture recognizes specific game messages independently of color settings; turning off a highlight does not stop chat capture. Ordinary room prose is not copied into COMBAT.

## Examples DGHUD recognizes

Room speech includes forms such as:

```text
Kaida says, "Hello."
Eilan asks Atrax, "Ready?"
You say I'm new.
```

Direct communication in PRIVATE includes:

```text
Xarus whispers, "I do not know."
Tekk thinks to you, "hello"
```

Shared communication in LINK includes:

```text
Tekk (ESP): "hello"
You pick up Losmir's mental link, "test"
You pick up Tekk's Psycian link, "hello" [r-1]
You pick up Tekk's Dragon link, "hello" [r-1]
You pick up Marcelline's Secian link, "Hello?" [r-1]
You pick up Faolann's thoughts echoing through the area, "leave me be"
```

Recognized staff-style communication includes forms such as:

```text
[GUIDE] Azaelia: Hello
[GM] Kaida: Hello
Nythriss'a sends: check check
You hear the voice of Wizzy say, "test"
You hear the voice of Wizzy ask Tamalon, "ready?"
```

Referral list entries, handling notices, and details also go to **STAFF**:

```text
1. Corin refers Aerin North (sample-user): 'Please check this sample quest.' [2 days ago.]
[GM] Keeper is handling Corin's referral. (3 more pending.)
<Corin refers Aerin North (sample-user): 'Please check this sample quest.'>
```

Wrapped referral lines are joined with spaces and saved as one **STAFF** message. The normal game display is unchanged. **SHOW IN ALL → STAFF** controls whether referrals also appear in **ALL**; STAFF capture and saved history continue when it is OFF. Completed referrals appear immediately; wrapped messages wait briefly for their final line.

WORLD recognizes server notices with any character name, including full names:

```text
** Obatalla Ogoun just arrived in the world.
** Xlade Vespar just arrived in the world.
** Obatalla Ogoun has left the world.
** Mael Soultis has left the world unexpectedly.
```

Parsing is intentionally specific. DGHUD does not capture every line containing words such as `says` or `whispers`, because room scripts and NPC output can use those words too.

Stat increases such as `Your will has increased!` and `Your constitution has increased!` are saved directly to **ALL**, even when COMBAT is excluded there. Supported stats are strength, intelligence, wisdom, dexterity, agility, constitution, charisma, will, presence, perception, and luck, plus the older voice and appearance names. The original message is preserved; these notices do not invent a new stat value.

`Due to your diligent training, you have gained additional fatigue!` is also saved directly to **ALL**, with the full notice preserved.

Skill improvements such as `You now feel more skilled in Biting.` are saved directly to **ALL** for any skill, including multi-word names. The original message is preserved, even when COMBAT is excluded from ALL.

## Scrolling and wrapping

Chat text wraps to the current width of the center display. DGHUD recalculates the wrap width and font when Mudlet is resized.

The scroll bar lets you read older visible entries. When you are already at the bottom, new messages keep the view at the bottom. When you are reading older messages, DGHUD tries to preserve that reading position.

Each message source keeps its own recent history (up to 1,000 entries by default). A busy COMBAT channel no longer pushes ordinary conversations out of their tabs, even when combat is hidden from ALL. Your own speech shares ROOM's history, and custom categories share a separate allowance. Updates carry all of these histories forward, not just the current tab.

Each displayed tab shows the newest 1,000 matching entries. ALL first applies your SHOW IN ALL choices, then its display limit. Older messages remain in the dated local history files, which are not automatically pruned or uploaded.

## Duplicate messages

Identical adjacent entries with the same category, speaker, target, and message are ignored once within the short deduplication window. A legitimate repeat later remains in the history. Identical text delivered privately and as a room/global broadcast remains separate, as does text delivered through distinct ESP, contact, and generic-link formats; matching GMCP/text copies still deduplicate.

## Add a custom capture trigger

DGHUD never edits personal triggers. You can create your own Mudlet trigger and call the stable capture function from its script.

To save the complete triggering line under a new `QUEST` category:

```lua
DGHUD.chat.capture("QUEST", line)
```

To save text you already extracted:

```lua
DGHUD.chat.capture("EVENTS", "The invasion has started.")
```

Use a short category name made from letters, numbers, spaces, underscores, or hyphens. The category is normalized for the chatbox and becomes a filter automatically.

Before calling the API from a reusable trigger, you may safely check that it exists:

```lua
if DGHUD and DGHUD.chat and DGHUD.chat.capture then
  DGHUD.chat.capture("QUEST", line)
end
```

## Check chat status

Enter:

```text
dghud chatstatus
```

It reports the active filter, visible-entry count, profile storage key, and newest storage error. It does not print your stored private messages.

## Local storage and privacy

Chat is stored as plain JSON Lines under:

```text
<Mudlet home>/DGHUDData/chat/profile/YYYY-MM-DD.jsonl
```

Updates, reloads, character changes, rollback, and uninstalling the package do not delete these files. Anyone who can read the Mudlet profile, computer account, backup, or copied profile data may be able to read private communications saved there.

DGHUD does not upload chat history in feedback or diagnostic reports.

See [Support, Privacy, and Saved Files](SUPPORT_PRIVACY_AND_FILES.md) for more detail.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
