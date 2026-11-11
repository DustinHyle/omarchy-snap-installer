-- Installed by omarchy-snap-installer. Personal gap settings are preserved.
local edgesnap = require("hypr.edgesnap")

hl.config({ general = { snap = { enabled = true, respect_gaps = true } } })

local function snap_action(action, fallback)
  return function()
    local _, available = edgesnap.action(action)
    if not available then hl.exec_cmd("omarchy-window-snap " .. fallback) end
  end
end

-- Replaces the default move-window-to-group actions on these keys.
o.rebind("SUPER + ALT + LEFT", "Snap window left", snap_action("left", "left"))
o.rebind("SUPER + ALT + RIGHT", "Snap window right", snap_action("right", "right"))
o.rebind("SUPER + ALT + UP", "Maximize window", snap_action("maximize", "maximize"))
o.rebind("SUPER + ALT + DOWN", "Restore window", snap_action("restore", "down"))

-- Corrected outer-zone geometry, including each window's titlebar and border.
o.rebind("SUPER + SHIFT + Home", "Snap window top left", "omarchy-window-snap top-left")
o.rebind("SUPER + SHIFT + Page_Up", "Snap window top right", "omarchy-window-snap top-right")
o.rebind("SUPER + SHIFT + End", "Snap window bottom left", "omarchy-window-snap bottom-left")
o.rebind("SUPER + SHIFT + Page_Down", "Snap window bottom right", "omarchy-window-snap bottom-right")
