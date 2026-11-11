# Omarchy mouse + keyboard snapping

Run these commands in a terminal **inside the target Omarchy desktop**, as your
normal user:

```bash
git clone https://github.com/DustinHyle/omarchy-snap-installer
cd omarchy-snap-installer
bash install.sh --check
bash install.sh
```

Do **not** run the installer with sudo. It asks for your password **once**
(or not at all if already authorized/passwordless); hyprpm still asks you to
confirm repository operations. Keep the whole
directory together, and keep it if you want to run `uninstall.sh` later. No
logout is normally needed.

## Requirements

- **Omarchy 4.5.0 or newer** (the Lua desktop config with the `o.rebind`
  helper). The installer stops on older versions; run `omarchy update` first.
- Running Hyprland desktop, internet access, and sudo permission.
- Upstream plugin compatibility with your installed Hyprland. Tested on Omarchy
  4.5.0 with Hyprland 0.56.2; upstream also documents 0.57.2 support. Builds can
  fail on newer, unsupported versions.

## The third-party plugin

The installer builds the MIT-licensed compositor plugin
[LordMelkor/hypr-edgesnap](https://github.com/LordMelkor/hypr-edgesnap)
through hyprpm on the target system. Plugins run inside Hyprland, with access
to all input and screen content, so the plugin is **pinned to a reviewed
commit** (`PIN` in `lib.sh`). hyprpm keeps building that exact commit, including
from the post-update hook, so new upstream code is never pulled in on its own.
To move to a newer upstream release, review its changes, update `PIN`, and
rerun `install.sh`. If hypr-edgesnap was already added to hyprpm without this
pin, the installer removes and re-adds it (hyprpm asks you to confirm).

Before replacement, it saves the previous registration, enabled state, and
built plugin. If replacement is cancelled, a build fails, or config validation
fails, it restores that snapshot **without needing the network or a rebuild**.
The snapshot is taken after the initial `hyprpm update`; that update and other
hyprpm repositories are not rolled back. A failed fresh install removes its
new registration. Recovery failures (for example revoked sudo authorization)
are reported with the saved plugin files' location.

### One-password authorization

hyprpm normally invalidates sudo's authorization after each command. During
install/uninstall only, a private temporary PATH shim defers **only** its bare
`sudo -k` calls. Other sudo calls are forwarded to the real sudo with `-n`
(never a hidden password prompt); a keepalive refreshes the timestamp during
long builds. Cleanup stops the keepalive, removes the shim, and invalidates
authorization, including on errors, Ctrl+C, and termination.

Passwords are handled solely by sudo: never captured, stored, or passed through
the installer. No sudoers or system-wide policy changes are made, and plugin
compilation remains unprivileged. If your sudo policy disables timestamp
caching, installation stops with an explanation instead of repeatedly prompting.
If another process invalidates authorization during installation, rerun it.

## Controls

Drag a floating window by its titlebar, or with **Super + left-drag**:

- Left/right edge: half screen.
- Corner: quarter screen.
- Top edge: maximize.
- Drag away: restore previous size.

Keyboard:

| Shortcut | Action |
|---|---|
| Super + Alt + Left/Right | Left/right half |
| Super + Alt + Up | Maximize |
| Super + Alt + Down | Restore |
| Super + Shift + Home | Top left |
| Super + Shift + Page Up | Top right |
| Super + Shift + End | Bottom left |
| Super + Shift + Page Down | Bottom right |

These replace any existing actions on those eight shortcuts, including
Omarchy's default Super+Alt+arrow move-window-into-group bindings. Other
bindings are untouched.

- Tiled windows are floated first, then snapped. Grouped windows are left alone.
- Mouse snapping and keyboard halves/maximize/restore share the plugin's
  restore memory. **Keyboard quarters use a standalone helper and do not create
  restore records**, so Super+Alt+Down does not undo them.
- If the plugin is not loaded or is disabled, halves and maximize use the
  standalone helper, and restore does nothing.
- Quarter geometry uses the configured border size and detected Hyprbar
  height; per-window border overrides or unusual decorations can be off by a
  few pixels.

The installer also turns on Hyprland's built-in floating-window edge alignment
(`general:snap` with `respect_gaps`). Gap sizes and monitor settings are not
changed.

## Settings

Put personal plugin options in `~/.config/hypr/edgesnap-local.lua`. The
installer never touches this file, so the settings survive reinstalling:

```lua
return {
  enabled = false,   -- turn off drag snapping; keyboard snapping keeps working
  columns = "auto",  -- "2" (default), "3", or "auto" (thirds above 16:9)
}
```

Then run `hyprctl reload` and check `hyprctl configerrors`. Do not edit the
installed `edgesnap.lua` or `window-snap.lua`: reinstalling replaces them.

## Installed files

- `~/.config/hypr/edgesnap.lua`: plugin load and options.
- `~/.config/hypr/window-snap.lua`: shortcuts and built-in edge alignment.
- `~/.local/bin/omarchy-window-snap`: quarter geometry and fallback helper.
- `~/.local/bin/hypr-edgesnap-check`: plugin presence check (run at login).
- `~/.config/omarchy/hooks/post-update.d/50-hyprpm-rebuild`: rebuilds hyprpm
  plugins after Omarchy updates, then reloads the config. It rebuilds **all**
  hyprpm-managed plugins. If sudo would need a password and nobody can answer
  (for example `omarchy update -y`), it skips the rebuild and says so; then run
  `hyprpm update` yourself.
- One marked `require` line appended to `~/.config/hypr/hyprland.lua`.

Files replaced on each install are backed up under
`~/.local/state/omarchy-snap-backup.XXXXXXXX/`; the installer prints that
directory, and `new-files.txt` there lists paths that did not exist before.
If installation fails after it starts changing files, it puts all of them back
automatically. Rerunning does not add duplicate load lines.

### Migrating the original manual installation

The installer recognizes the exact script-backed and plugin-backed snapping
blocks from the original manual setup in `bindings.lua`. It removes only those
blocks, their old standalone `require("hypr.edgesnap")` line, and the matching
edge-alignment block from `looknfeel.lua`. The installer-managed module then
owns the snapping shortcuts/settings. Dictation bindings, gaps, and unrelated
configuration are preserved. A modified legacy block causes installation to
stop for manual review rather than guessing what to delete. All affected files
are backed up, and config failure restores them.

After a Hyprland upgrade, a new session or reboot may be needed before the
rebuilt plugin loads. You get a notification at login if it did not load.

## Uninstall

```bash
bash uninstall.sh
```

This removes the load line, the installed files (only ones the installer
wrote), and the hyprpm registration, then reloads Hyprland, which restores
Omarchy's default Super+Alt+arrow bindings. Your `edgesnap-local.lua` and the
installer's backups are kept.

## Tests

```bash
python3 -m unittest discover -s tests -v
```

Tests use temporary homes and fake sudo/hyprpm/Hyprland commands: they never
install packages, request real privilege, or modify the running desktop. They
cover migration, reinstalling, single-password authorization, cancelled plugin
operations, build/config failures, and restoration of the original plugin.
