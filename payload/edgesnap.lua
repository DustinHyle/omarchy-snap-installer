-- Installed by omarchy-snap-installer; reinstalling replaces this file.
-- Put personal settings in ~/.config/hypr/edgesnap-local.lua instead (see
-- README), which the installer never touches.
--
-- hypr-edgesnap: Windows Aero Snap-style drag snapping for floating windows.
-- Drag a window to an edge for a half, a corner for a quarter, or the top edge
-- to maximize; a preview shows the target. Dragging a snapped window away
-- gives it its pre-snap size back. The keyboard bindings in window-snap.lua
-- call the same plugin functions, so keyboard and mouse share one restore
-- record per window.
--
-- hyprpm builds the plugin and records it as enabled. Loading it here, rather
-- than running `hyprpm reload` at login, keeps Omarchy's own plugins (such as
-- hyprbars) loaded: hyprpm would otherwise unload the ones it does not manage.
-- `hyprpm update` rebuilds it after a Hyprland upgrade (see the post-update
-- hook installed with this setup).

local home = os.getenv("HOME") or ""

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then return false end
  file:close()
  return true
end

-- hyprpm keys its cache by the real account name, which $USER may not match.
local function account_name()
  local pipe = io.popen("id -un 2>/dev/null")
  local name = pipe and pipe:read("*l")
  if pipe then pipe:close() end
  if name and name ~= "" then return name end
  return os.getenv("USER") or os.getenv("LOGNAME") or ""
end

local plugin_path = "/var/cache/hyprpm/" .. account_name() .. "/hypr-edgesnap/hypr-edgesnap.so"
if file_exists(plugin_path) then
  hl.plugin.load(plugin_path)
end

local options = {
  columns = "2", -- "3" or "auto" adds thirds when dragging to an edge
  quarters = true,
  gaps = true,
}

-- edgesnap-local.lua returns a table of plugin options, e.g.
--   return { enabled = false, columns = "auto" }
-- Errors in it are reported like any other config error.
if file_exists(home .. "/.config/hypr/edgesnap-local.lua") then
  local overrides = require("hypr.edgesnap-local")
  if type(overrides) == "table" then
    for key, value in pairs(overrides) do options[key] = value end
  end
end

-- The plugin reloads the config once it is in, so this second pass finds it.
if hl.plugin.edgesnap then
  hl.config({ plugin = { edgesnap = options } })
end

local M = {}

-- Run one of the plugin's keyboard actions ("left", "right", "maximize",
-- "restore"). Returns the action's handled flag and whether the plugin ran at
-- all, so a caller can tell a missing plugin from a window it declined.
function M.action(name)
  local plugin = hl.plugin.edgesnap
  if plugin and type(plugin[name]) == "function" then
    local ok, handled = pcall(plugin[name])
    if ok then return handled and true or false, true end
  end
  return false, false
end

-- Report at login if the plugin is enabled in hyprpm but did not load.
hl.on("hyprland.start", function()
  hl.exec_cmd('[ -x "$HOME/.local/bin/hypr-edgesnap-check" ] && "$HOME/.local/bin/hypr-edgesnap-check" --wait 30 --notify')
end)

return M
