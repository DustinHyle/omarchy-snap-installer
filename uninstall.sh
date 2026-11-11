#!/usr/bin/env bash
# Removes what install.sh added. Run as your desktop user, without sudo.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$ROOT/lib.sh"

[[ $EUID != 0 ]] || fail "Run as your regular user, not with sudo."

cat <<INFO
This removes the snapping shortcuts, helper scripts, post-update hook, and the
load line in hyprland.lua, then removes hypr-edgesnap from hyprpm (hyprpm asks
to confirm). Files that were changed after installation are left in place.
Your edgesnap-local.lua settings file, if any, is kept.
INFO
read -r -p "Uninstall snapping? [y/N] " answer
[[ $answer == y || $answer == Y || $answer == yes ]] || exit 0

if [[ -f $CONFIG ]] && grep -Fqx -- "$LOAD" "$CONFIG"; then
  mkdir -p "$HOME/.local/state"
  saved=$(mktemp "$HOME/.local/state/omarchy-snap-uninstall.hyprland.lua.XXXXXXXX")
  cp -a -- "$CONFIG" "$saved"
  # Rewrite in place so the file keeps its permissions and any symlink.
  # Drops the load line and the blank line install.sh put before it.
  python3 -I -c '
import sys
text, load = open(sys.argv[1]).read(), sys.argv[2]
lines = text.split("\n")
out = [l for i, l in enumerate(lines)
       if l != load and not (l == "" and i + 1 < len(lines) and lines[i + 1] == load)]
sys.stdout.write("\n".join(out))
' "$saved" "$LOAD" > "$CONFIG"
  echo "Removed the load line from $CONFIG (previous copy: $saved)"
fi

for file in "${PAYLOAD[@]}"; do
  target=$(target_for "$file")
  [[ -e $target ]] || continue
  if cmp -s -- "$target" "$ROOT/payload/$file" || grep -q 'omarchy-snap-installer' -- "$target"; then
    rm -f -- "$target"
    echo "Removed $target"
  else
    echo "Kept $target: it does not look like a file this installer wrote."
  fi
done

if command -v hyprpm >/dev/null && registered_rev >/dev/null; then
  sudo_ready
  hyprpm --no-nix disable hypr-edgesnap || true
  sudo_ready
  hyprpm --no-nix remove hypr-edgesnap || echo "hyprpm did not remove hypr-edgesnap; run 'hyprpm remove hypr-edgesnap' later." >&2
fi

if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload >/dev/null || true
  errors=$(hyprctl configerrors 2>/dev/null) || errors=""
  [[ -z ${errors//[[:space:]]/} ]] || echo "Hyprland reports config errors: $errors" >&2
  if hyprctl -j plugin list 2>/dev/null | jq -e 'any(.[]; .name == "hypr-edgesnap")' >/dev/null; then
    echo "hypr-edgesnap is still loaded in this session; it unloads when you log out."
  fi
fi
echo "Uninstalled."
echo "Earlier installer backups remain in ~/.local/state/omarchy-snap-backup.*"
