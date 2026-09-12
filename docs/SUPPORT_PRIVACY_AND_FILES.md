# DGHUD Support, Privacy, and Saved Files

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

## Feedback and feature requests

Open **OPTIONS → SUPPORT → FEEDBACK & REQUESTS**.

1. Choose Feedback or Request.
2. Enter a short summary.
3. Describe what you saw, what you expected, and how to repeat it.
4. Submit it.

The form sends through the DGHUD service without opening a browser or requiring a GitHub account. A successful submission returns a reference.

Please include exact game or DGHUD wording when the request concerns a parser, chat line, color matcher, or error. Do not include passwords, private account information, private chat, access tokens, or API keys.

## Debug reports

When an updater, mapper, map library, or related operation fails, DGHUD records a small local report. It is not sent automatically.

To send the newest report:

1. Open **OPTIONS → SUPPORT**.
2. Click **SEND LAST DEBUG REPORT**.
3. Keep the returned reference number.

For a mapper-specific report, use **Map Settings → Map Library → REPORT A PROBLEM** or:

```text
dghud map debug
```

To keep a local mapper diagnostic and open its folder:

```text
dghud map debug folder
```

## What privacy-safe reports remove

General failure reports are bounded in size and sanitize or remove:

- URLs;
- email addresses;
- IP addresses;
- local user paths;
- token, authorization, API-key, and password-like values;
- quoted text; and
- unsupported control characters.

They include only a short recent list of DGHUD failure events and approved technical context such as operation, stage, scope, counts, schema, HTTP status, and Mudlet version.

Mapper diagnostics explicitly exclude credentials, chat, room descriptions, character names, IP addresses, and command history.

## Chat privacy

The top chatbox saves recognized communication locally, including private categories such as whispers, ESP, Dragon links, Secian links, and Contact messages.

Default location:

```text
<Mudlet home>/DGHUDData/chat/profile/YYYY-MM-DD.jsonl
```

These are plain local files. Anyone with access to the Mudlet profile, computer account, backups, or copied profile directory may be able to read them.

DGHUD does not include chat logs in diagnostics and does not upload chat history.

See [Chatbox](CHATBOX.md).

## Main DGHUD data directory

Enter:

```text
dghud config
```

DGHUD prints the exact persistent data location for the active profile. It is normally:

```text
<Mudlet profile home>/DGHUDData/
```

This directory may contain:

| Location | Purpose |
| --- | --- |
| `chat/profile/` | Dated local chat history. |
| `map-collections/` | Named local map collection snapshots and index data. |
| `maps/` | Private map exports, downloads, and transfer files. |
| `diagnostics/` | Local privacy-safe failure and mapper reports. |
| `og_dg_roller/` | Autoroller session and master logs by default. |
| `roller-settings.lua` | Saved autoroller preferences. |
| `mapper-settings.lua` | Saved automapper preferences. |
| `update-settings.lua` | Saved automatic-update choice. |
| `display-settings.lua` | Saved HUD text-size choice. |

File names or exact internal structure may expand in later releases. Use the built-in settings and library controls when possible.

## What updates do not remove

Updating or recovering DGHUD does not intentionally delete the persistent data directory. It also does not intentionally alter:

- personal triggers;
- personal aliases;
- personal scripts or timers;
- key bindings;
- unrelated packages;
- unrelated Mudlet settings; or
- personal/unowned map content.

## Backups

For maps, use **Map Settings → Map Library → MY MAPS → BACKUP** before a major edit, combine, or replacement.

For full profile protection, periodically back up the Mudlet profile while Mudlet is closed. Include `DGHUDData` if you want to retain chat, collections, settings, logs, and diagnostics.

## Deleting local data

Use specific in-HUD cleanup controls whenever possible:

- map commands remove only previewed DGHUD-owned map data;
- deleting a map collection affects only that selected collection;
- chat history is removed only by deleting its dated local files yourself; and
- package recovery should use `dghud recover`, not deletion of the entire data directory.

Before deleting files manually, close Mudlet and make a backup. The operation may not be recoverable after backups are removed.

## Community map submissions

Maps can be uploaded through the built-in library without a GitHub account. A submission contains the map data and the creator/publisher information entered for that map. It is validated and placed into a review queue before public publication.

Downloaded maps become separate local collections or new combined copies. Editing and reuploading a downloaded map does not silently overwrite the original creator's publication.

See [Automapper and Map Library](AUTOMAPPER_AND_MAP_LIBRARY.md).

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
