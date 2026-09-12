# DGHUD Chatbox Guide

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

The chatbox stays above the normal game display. It copies recognized communication into a separate readable history without gagging, replacing, or changing the original game line.

Chat history belongs to the Mudlet profile, not to one character. Switching characters in the same profile keeps the same history.

Use **OPTIONS → CHAT SETTINGS** to clear only the visible chatbox or permanently remove all saved DGHUD chat history. Permanent deletion requires two clicks; the command-line equivalent requires the full `dghud chat clear saved confirm` phrase.

## Built-in filters

- **ALL** — Every captured category.
- **ROOM** — Nearby speech and your own speech.
- **PRIVATE** — Whispers, ESP, Dragon links, Secian links, and contact-style thoughts together.
- **ESP** — ESP messages only.
- **DRAGON** — Mental and Dragon link messages.
- **CONTACT** — Thoughts echoing through the area.
- **STAFF** — Recognized Guide, GM, Elder, sends, and voice formats.
- **COMBAT** — Conservative incoming attacks, damage, movement blocks, spell threats, upkeep, recovery, and similar high-value combat lines.

If all tabs do not fit, the final overflow control cycles through hidden categories. Custom categories added by personal triggers become available as filters too. The built-in Combat filter uses the same narrow matching rules as DGHUD's optional combat coloring, so ordinary room prose is not copied into it.

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
