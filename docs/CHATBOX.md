# DGHUD Chatbox Guide

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

The chatbox appears above the normal game display by default. It copies recognized communication into a separate readable history without gagging, replacing, or changing the original game line.

To hide it completely, open **OPTIONS → CHAT SETTINGS** and set **SHOW CHATBOX: OFF**. The main game display expands into the freed space. Chat capture and saved history continue while hidden; this does not turn off logging. Return to the same setting and switch it **ON** to see your messages again. Your choice is saved for the profile and survives character changes, restarts, and HUD updates. It does not change your tab order or SHOW IN ALL choices.

Chat history belongs to the Mudlet profile, not to one character. Switching characters in the same profile keeps the same history.

Use **OPTIONS → CHAT SETTINGS** to clear only the visible chatbox or permanently remove all saved DGHUD chat history. Permanent deletion requires two clicks; the command-line equivalent requires the full `dghud chat clear saved confirm` phrase.

The same settings window has a **SHOW IN ALL** section. Toggle any source to control whether it appears in the combined **ALL** tab. `COMBAT` starts off there; every other source starts on. This changes only the combined view—dedicated tabs continue to work, capture continues, and saved history is untouched. The choices persist through profile restarts and HUD updates.

## Sound alerts

Open **OPTIONS → CHAT SETTINGS → SOUND ALERTS**. Each tab has an **ON/OFF** control, a choice of nine short sounds, and a **PREVIEW** button. Each built-in tab starts with a different sound. **STAFF starts ON; all other alerts start OFF.** You can change the shared alert volume too. Changes save immediately for this Mudlet profile and survive restarts, character changes, and HUD updates.

Preview lets you hear a sound even when that tab's alerts are OFF; it does not turn the alert on. The sounds are created locally from tones included in the HUD—no external media download or account is required. Mudlet's **Mute all media** and your computer's audio settings still apply.

Only newly captured messages alert. Loading saved history, scrolling, switching tabs, changing characters, and updating the HUD do not replay old alerts. Rapid messages are limited to one alert per second per selected tab.

A message can appear in more than one filter, but plays only one sound: its specific enabled tab takes priority, then **PRIVATE** for private channels, then **ALL** if the message is included there. For example, enabling ESP and ALL does not make ESP messages ding twice. Hiding the chatbox does not mute alerts; turn off its alert switches when you want silence. Custom tabs appear in the sound settings after they are created and start OFF.

## Built-in filters

- **ALL** — Every captured category.
- **ROOM** — Nearby speech and your own speech.
- **PRIVATE** — Whispers, ESP, Dragon links, Secian links, and contact-style thoughts together.
- **ESP** — ESP messages only.
- **DRAGON** — Mental and Dragon link messages.
- **CONTACT** — Thoughts echoing through the area.
- **STAFF** — Recognized Guide, GM, Elder, sends, and voice formats.
- **COMBAT** — Conservative incoming attacks, damage, movement blocks, spell threats, upkeep, recovery, and similar high-value combat lines.

Drag any chat tab left or right to arrange the filters in the order you prefer. The order is saved for the whole Mudlet profile and survives character changes, reconnects, and HUD updates. A short click still selects the tab normally.

If all tabs do not fit, the final overflow control cycles through hidden categories. Custom categories added by personal triggers become available as filters too, and can be reordered after they appear. The built-in Combat filter uses the same narrow matching rules as DGHUD's optional combat coloring, so ordinary room prose is not copied into it.

## Examples DGHUD recognizes

Room speech includes forms such as:

```text
Kaida says, "Hello."
Eilan asks Atrax, "Ready?"
You say I'm new.
```

Private communication includes forms such as:

```text
Xarus whispers, "I do not know."
Tekk (ESP): "hello"
You pick up Losmir's mental link, "test"
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

Parsing is intentionally specific. DGHUD does not capture every line containing words such as `says` or `whispers`, because room scripts and NPC output can use those words too.

## Scrolling and wrapping

Chat text wraps to the current width of the center display. DGHUD recalculates the wrap width and font when Mudlet is resized.

The scroll bar lets you read older visible entries. When you are already at the bottom, new messages keep the view at the bottom. When you are reading older messages, DGHUD tries to preserve that reading position.

The in-memory view is limited to the newest 1,000 valid entries by default. The local history files are not automatically pruned.

## Duplicate messages

Identical adjacent entries with the same category, speaker, target, and message are ignored once within the short deduplication window. A legitimate repeat later remains in the history.

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
