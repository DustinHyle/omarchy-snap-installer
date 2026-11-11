# Omarchy mouse + keyboard snapping

Run these commands in a terminal **inside the target Omarchy desktop**, as your
normal user:

```bash
git clone https://github.com/DustinHyle/omarchy-snap-installer
cd omarchy-snap-installer
bash install.sh --check
bash install.sh
```

Do **not** run the installer with sudo. It asks for sudo when needed; hyprpm
also asks you to confirm adding the plugin repository. Keep the whole
directory together, and keep it if you want to run `uninstall.sh` later. No
logout is normally needed.

## Requirements

- **Omarchy 4.5.0 or newer** (the Lua desktop config with the `o.rebind`
  helper). The installer stops on older versions; run `omarchy update` first.
- Running Hyprland desktop, internet access, and sudo permission.
- Upstream plugin compatibility with your installed Hyprland. Tested on
  0.56.2; upstream also documents 0.57.2 support. Builds can fail on newer,
  unsupported versions.

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

After a Hyprland upgrade, a new session or reboot may be needed before the
rebuilt plugin loads. You get a notification at login if it did not load.

## Uninstall

```bash
bash uninstall.sh
```

This removes the load line, the installed files (only ones the installer
wrote), and the hyprpm registration, then reloads Hyprland. A plugin that is
already loaded stays active until you log out. Your `edgesnap-local.lua` and
the installer's backups are kept.
