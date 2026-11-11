-- hypr-edgesnap: Windows Aero Snap-style drag snapping for floating windows.
--
-- Drag a window to an edge for a half, a corner for a quarter, or the top edge
-- to maximize; a preview shows the target. Dragging a snapped window away
-- gives it its pre-snap size back. The keyboard bindings in hypr/bindings.lua
-- call the same plugin functions, so keyboard and mouse share one restore
-- record per window.
--
-- hyprpm builds the plugin and records it as enabled. Loading it here, rather
-- than running `hyprpm reload` at login, keeps Omarchy's own plugins (such as
-- hyprbars) loaded: hyprpm would otherwise unload the ones it does not manage.
-- `hyprpm update` rebuilds it after a Hyprland upgrade (see the post-update
-- hook installed with this setup).

local home = os.getenv("HOME") or ""
local user = os.getenv("USER") or os.getenv("LOGNAME") or home:match("([^/]+)$") or ""
local plugin_path = "/var/cache/hyprpm/" .. user .. "/hypr-edgesnap/hypr-edgesnap.so"

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then return false end
  file:close()
  return true
end

if file_exists(plugin_path) then
  hl.plugin.load(plugin_path)
end

-- The plugin reloads the config once it is in, so this second pass finds it.
if hl.plugin.edgesnap then
  hl.config({
    plugin = {
      edgesnap = {
        columns = "2", -- "3" or "auto" adds thirds when dragging to an edge
        quarters = true,
        gaps = true,
      },
    },
  })
end

local M = {}

-- Run one of the plugin's keyboard actions ("left", "right", "maximize",
-- "restore"). Returns the action's handled flag and whether the plugin ran at
-- all, so a caller can fall back only when the plugin is missing or errored,
-- not when it declined a window it is not meant to touch.
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
