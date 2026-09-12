# DGHUD Updates and Emergency Recovery

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)

DGHUD supports manual update checks, manual updates, an optional login-time update setting, and an independent emergency recovery command.

## Check without installing

Enter:

```text
dghud check
```

DGHUD prints the installed version and whether a newer release exists. It does not replace the package.

## Install an update

Enter:

```text
dghud update
```

DGHUD first checks the latest release. If the installed version is already current, it reports that and does not reinstall the same package.

When a newer release exists, the updater:

1. downloads release metadata and its versioned manifest;
2. checks the repository, version, Mudlet requirement, package name, URL, and size limits;
3. downloads the exact versioned package;
4. verifies its SHA-256 checksum;
5. prepares a rollback copy;
6. replaces only the `DragonsGateHUD` package;
7. waits for a running, healthy HUD; and
8. refreshes character data after a successful replacement.

Normal update messages show elapsed time for the major stages. Large Mudlet profiles and native profile saving can make package replacement take longer than the download itself.

Do not enter `dghud update` repeatedly while one update is still running.

## Automatic updates

Automatic updates are off by default. Toggle them through **OPTIONS → AUTOMATIC UPDATES**.

When enabled, DGHUD attempts the same verified update process after entering a character. When disabled, it skips network update work and immediately starts the normal character-data refresh.

The setting is stored separately from the package. Updating DGHUD does not change your choice.

For maximum control, leave automatic updates off, run `dghud check`, and update manually at a convenient time.

## What an update preserves

An update is scoped to the DGHUD package. It is designed to preserve:

- personal Mudlet triggers, aliases, scripts, timers, keys, and settings;
- unrelated packages;
- unrelated or personal native map content;
- DGHUD map collections and exports;
- chat history;
- roller settings and logs;
- mapper settings;
- HUD text size;
- automatic-update preference; and
- local diagnostics.

Mutable DGHUD data is stored under the profile's `DGHUDData` directory, outside the replaceable package directory.

## If an update fails

Do not keep rerunning it immediately. The current HUD or rollback copy may still be active.

1. Read the complete `[DGHUD Update]` error.
2. Wait for Mudlet to finish any profile save.
3. Enter `dghud check` once.
4. If the HUD is still visible, use **OPTIONS → SUPPORT → SEND LAST DEBUG REPORT**.
5. If the HUD is missing or unhealthy, use emergency recovery.

An update failure creates a bounded privacy-safe report under `DGHUDData/diagnostics`. It is not uploaded until you choose to send it.

## Emergency recovery

Enter:

```text
dghud recover
```

This command belongs to the separate `DGHUDRecovery` companion, not to the main HUD. The companion is maintained after a successful HUD start so the command can remain available even when the main package is missing or broken.

Recovery:

1. downloads a clean current package;
2. verifies that personal data is safely outside the replaceable package;
3. preserves the current visible HUD when possible;
4. removes only the broken `DragonsGateHUD` package;
5. installs the clean package; and
6. waits for a healthy running HUD before reporting success.

It does not intentionally delete `DGHUDData` or unrelated Mudlet content.

## If `dghud recover` is unknown

Install the recovery companion directly, then run the command again:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/latest/download/DGHUDRecovery.mpackage")
```

Then:

```text
dghud recover
```

If the recovery download was accepted but the HUD did not activate, close and reopen the affected Mudlet profile and run `dghud recover` once more.

## Very old installations

If updating from DGHUD 0.3.15 or older, first install the migration bridge:

```lua
lua installPackage("https://github.com/wizzydizzy-ctrl/dragons-gate-player-hud/releases/latest/download/DGHUDMigration.mpackage")
```

This protects personal files that older versions may have placed inside the package directory.

## Reload is not an update

```text
dghud reload
```

Reload rebuilds the current installed HUD with saved preferences. It does not contact GitHub or install a newer version. Use it for a visual problem after resizing or a setting change, not for a failed package installation.

## Avoid manual package removal unless necessary

Removing `DragonsGateHUD` through Mudlet's Package Manager is different from clearing maps or local data. If the goal is to repair the HUD, prefer `dghud recover` because it performs data checks and verifies the replacement.

The `dghud purge` name may appear in an older short command list, but it is not the recommended repair path. Use the specific map cleanup controls for maps and recovery for package repair.

[Back to the Complete DGHUD Guide](DGHUD_GUIDE.md)
