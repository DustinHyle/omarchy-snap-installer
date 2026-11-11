-- Installed by omarchy-snap-installer; reinstalling replaces this file.
-- Personal gap settings are preserved.
local edgesnap = require("hypr.edgesnap")

-- Hyprland's built-in edge alignment for floating windows.
hl.config({ general = { snap = { enabled = true, respect_gaps = true } } })

-- The plugin only acts on floating windows outside groups, and Omarchy tiles
-- windows by default. A tiled window is floated first and handed back to the
-- plugin, so it still gets a restore record. When the plugin is missing or
-- disabled, the standalone helper places the window instead. Grouped windows
-- are left alone. Actions without a fallback (restore) never float a window.
local function snap_action(action, fallback)
  return function()
    local handled, available = edgesnap.action(action)
    if handled then return end

    local window = hl.get_active_window()
    if not window or window.group or not fallback then return end

    if available and not window.floating then
      hl.dispatch(hl.dsp.window.float({ action = "set", window = "address:" .. window.address }))
      if edgesnap.action(action) then return end
    end
    hl.exec_cmd("omarchy-window-snap " .. fallback)
  end
end

-- Replaces Omarchy's default move-window-into-group actions on these keys.
o.rebind("SUPER + ALT + LEFT", "Snap window left", snap_action("left", "left"))
o.rebind("SUPER + ALT + RIGHT", "Snap window right", snap_action("right", "right"))
o.rebind("SUPER + ALT + UP", "Maximize window", snap_action("maximize", "maximize"))
o.rebind("SUPER + ALT + DOWN", "Restore window", snap_action("restore", nil))

-- Quarters use the helper's outer-zone geometry, including each window's
-- titlebar and border. They do not create plugin restore records.
o.rebind("SUPER + SHIFT + Home", "Snap window top left", "omarchy-window-snap top-left")
o.rebind("SUPER + SHIFT + Page_Up", "Snap window top right", "omarchy-window-snap top-right")
o.rebind("SUPER + SHIFT + End", "Snap window bottom left", "omarchy-window-snap bottom-left")
o.rebind("SUPER + SHIFT + Page_Down", "Snap window bottom right", "omarchy-window-snap bottom-right")
