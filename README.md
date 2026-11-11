# Omarchy mouse + keyboard snapping

Copy `omarchy-snap-installer.tar.gz` to the other system and run these commands
in a terminal **inside its Omarchy desktop**, as your normal user:

```bash
tar -xzf omarchy-snap-installer.tar.gz
cd omarchy-snap-installer
bash install.sh --check
bash install.sh
```

Do **not** run the installer with sudo. It asks for sudo when needed; hyprpm
also asks you to confirm adding the plugin repository. Keep the whole extracted
directory together. No logout is normally needed.

## Requirements

- Recent Omarchy using `~/.config/hypr/hyprland.lua` and its `o.rebind` helper.
- Running Hyprland desktop, internet access, and sudo permission.
- Upstream plugin compatibility with your installed Hyprland. Tested here on
  0.56.2; upstream also documents 0.57.2 support. Older `.conf` setups are not
  supported. Builds can fail on unsupported newer versions.

The installer downloads/builds the MIT-licensed third-party compositor plugin
[LordMelkor/hypr-edgesnap](https://github.com/LordMelkor/hypr-edgesnap).
It does not copy this machine's binary: hyprpm builds for the target system.
Plugins execute inside Hyprland and carry compositor stability/security risks.

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

These replace any existing actions on those eight shortcuts, including the
default Super+Alt+arrow group-movement bindings. Other bindings are untouched.
Mouse snapping and keyboard halves/maximize/restore share the plugin's restore
memory. **Keyboard quarters use the corrected standalone helper and do not
create shared restore records.** Like the source setup, quarter geometry uses
the configured border size and detected Hyprbar height; per-window border
overrides or unusual decorations can need additional adaptation.

## Installed files

- `~/.config/hypr/edgesnap.lua`: plugin load and options.
- `~/.config/hypr/window-snap.lua`: shortcuts and built-in edge alignment.
- `~/.local/bin/omarchy-window-snap`: corrected quarter geometry.
- `~/.local/bin/hypr-edgesnap-check`: plugin presence check.
- `~/.config/omarchy/hooks/post-update.d/50-hyprpm-rebuild`: rebuilds hyprpm
  plugins after Omarchy updates, then reloads the config.
- One marked `require` line appended to `~/.config/hypr/hyprland.lua`.

Gap sizes and monitor settings are not changed. Files replaced on each install
are backed up under `~/.local/state/omarchy-snap-backup.XXXXXXXX/`; the installer
prints that directory. `new-files.txt` lists paths that did not previously exist.
Rerunning does not append duplicate load lines. Existing files with these names
are replaced (and backed up).

After a Hyprland upgrade, a new session/reboot may be needed for plugins built
against the new version. The hook updates **all** hyprpm-managed plugins.

## Disable or remove

To disable drag snapping without changing keyboard bindings, add
`enabled = false,` inside the `plugin.edgesnap` options in `edgesnap.lua`.
Then run `hyprctl reload` and check `hyprctl configerrors`.

To undo this installation:

1. Remove only the line ending `-- omarchy-snap-installer` from
   `~/.config/hypr/hyprland.lua`.
2. Restore backed-up versions of the installed files listed above; if a file
   is listed in `new-files.txt`, remove that installed file instead. Leave
   unrelated hooks/config alone. Avoid restoring an old full `hyprland.lua`
   if you have made other edits since installation.
3. Run `hyprpm disable hypr-edgesnap`, then
   `hyprpm remove hypr-edgesnap` in a terminal, authenticating if requested.
4. Run `hyprctl reload` and `hyprctl configerrors`.

If installation fails, it stops and prints the error; backups remain available.
Package/plugin operations already completed are not automatically rolled back.
