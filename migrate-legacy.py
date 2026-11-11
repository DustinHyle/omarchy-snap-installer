#!/usr/bin/env python3
"""Remove only exact, known blocks from the original manual setup.

--check prints the migration plan without writing. --apply performs it after
the installer has backed up all affected files. Unknown edits are never guessed.
"""
import argparse
from pathlib import Path

LEGACY_HEADER = '-- Windows-style window snapping (floating windows, including the floating\n'
QUARTERS = '''-- Direct quarter bindings, laid out like the navigation cluster.
o.bind("SUPER + SHIFT + Home", "Snap window top left", "omarchy-window-snap top-left")
o.bind("SUPER + SHIFT + Page_Up", "Snap window top right", "omarchy-window-snap top-right")
o.bind("SUPER + SHIFT + End", "Snap window bottom left", "omarchy-window-snap bottom-left")
o.bind("SUPER + SHIFT + Page_Down", "Snap window bottom right", "omarchy-window-snap bottom-right")
'''
PLUGIN_BINDINGS = LEGACY_HEADER + '''-- desktop layout). Halves, maximize and restore go through hypr-edgesnap so
-- they share its restore memory with mouse drag snapping: after any of them,
-- SUPER + ALT + DOWN returns the window to the size it had before its first
-- snap. If the plugin is missing, the bindings fall back to the shell helper.
-- These replace the tiling "move window to group" bindings on the same keys.
local edgesnap = require("hypr.edgesnap")

local function snap_action(action, fallback)
  return function()
    local _, handled = edgesnap.action(action)
    if not handled then hl.exec_cmd("omarchy-window-snap " .. fallback) end
  end
end

o.rebind("SUPER + ALT + LEFT", "Snap window left", snap_action("left", "left"))
o.rebind("SUPER + ALT + RIGHT", "Snap window right", snap_action("right", "right"))
o.rebind("SUPER + ALT + UP", "Maximize window", snap_action("maximize", "maximize"))
o.rebind("SUPER + ALT + DOWN", "Restore window", snap_action("restore", "down"))

''' + QUARTERS
SCRIPT_BINDINGS = LEGACY_HEADER + '''-- desktop layout). Snap to a half, then press a perpendicular arrow to take
-- the quarter on that side: SUPER + ALT + LEFT, then UP gives top-left.
-- These replace the tiling "move window to group" bindings on the same keys.
o.rebind("SUPER + ALT + LEFT", "Snap window left", "omarchy-window-snap left")
o.rebind("SUPER + ALT + RIGHT", "Snap window right", "omarchy-window-snap right")
o.rebind("SUPER + ALT + UP", "Snap window up", "omarchy-window-snap up")
o.rebind("SUPER + ALT + DOWN", "Snap window down", "omarchy-window-snap down")

''' + QUARTERS
ALIGNMENT = '''
    -- Snap floating windows to monitor and window edges while dragging.
    snap = {
      enabled = true,
      respect_gaps = true,
    },
'''


def plan(home):
    directory = Path(home) / '.config/hypr'
    path = directory / 'bindings.lua'
    text = path.read_text() if path.exists() else ''
    updated = text
    for block in (PLUGIN_BINDINGS, SCRIPT_BINDINGS):
        updated = updated.replace(block + '\n', '').replace(block, '')
    if LEGACY_HEADER in updated:
        raise ValueError('Modified legacy snapping block in bindings.lua: migrate it manually; no files were changed.')
    changes = {}
    if updated != text:
        changes[path] = updated
        path = directory / 'hyprland.lua'
        text = path.read_text()
        updated = ''.join(line for line in text.splitlines(keepends=True)
                          if line.rstrip('\r\n') != 'require("hypr.edgesnap")')
        if text != updated:
            changes[path] = updated
        path = directory / 'looknfeel.lua'
        if path.exists():
            text = path.read_text()
            updated = text.replace(ALIGNMENT, '')
            if text != updated:
                changes[path] = updated
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--check', action='store_const', const='check', dest='mode')
    modes.add_argument('--apply', action='store_const', const='apply', dest='mode')
    args = parser.parse_args()
    try:
        changes = plan(Path.home())
    except ValueError as error:
        parser.exit(1, f'{error}\n')
    for path, text in changes.items():
        print(f'Legacy snapping migration: {path}')
        if args.mode == 'apply':
            path.write_text(text)


if __name__ == '__main__':
    main()
