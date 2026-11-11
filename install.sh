#!/usr/bin/env bash
# Run as your desktop user, in a terminal inside an Omarchy Hyprland session.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG="$HOME/.config/hypr/hyprland.lua"
LOAD='require("hypr.window-snap") -- omarchy-snap-installer'
URL=https://github.com/LordMelkor/hypr-edgesnap
MODE=${1:-install}

case "$MODE" in
  --help|-h)
    echo "Usage: bash install.sh [--check]"
    echo "Run without sudo, in a terminal on the target Omarchy desktop."
    echo "--check validates prerequisites without changing anything."
    exit 0 ;;
  install|--check) ;;
  *) echo "Unknown option: $MODE" >&2; exit 2 ;;
esac

fail() { echo "Error: $*" >&2; exit 1; }
[[ $EUID != 0 ]] || fail "Run as your regular user, not with sudo."
for cmd in omarchy hyprctl python3 jq sudo; do
  command -v "$cmd" >/dev/null || fail "Missing required command: $cmd"
done
[[ -f "$CONFIG" ]] || fail "This installer needs Omarchy's Lua config at $CONFIG (not legacy hyprland.conf)."
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || fail "Run inside the target Hyprland desktop session."
hyprctl -j version >/dev/null || fail "Cannot reach Hyprland."
errors=$(hyprctl configerrors)
[[ -z ${errors//[[:space:]]/} ]] || fail "Fix existing Hyprland config errors first: $errors"
for file in edgesnap.lua window-snap.lua omarchy-window-snap hypr-edgesnap-check 50-hyprpm-rebuild; do
  [[ -f "$ROOT/payload/$file" ]] || fail "Missing payload/$file; extract the whole archive."
done

echo "Prerequisites OK. Running Hyprland:"
hyprctl -j version | jq -r '.version // .tag // .commit'
[[ $MODE != --check ]] || exit 0

cat <<'INFO'

This installs the third-party hypr-edgesnap compositor plugin through hyprpm.
Plugins run inside Hyprland; builds depend on your Hyprland version and can
fail if upstream has not added support yet. Internet access and sudo are needed.

It adds Super+Alt+arrows and Super+Shift+Home/Page Up/End/Page Down,
replacing any existing actions on those keys. Other bindings, monitor settings,
and your existing gap sizes are preserved. Replaced files are backed up.
INFO
read -r -p "Install snapping? [y/N] " answer
[[ $answer == y || $answer == Y || $answer == yes ]] || exit 0

# Keep backups outside ~/.config so they cannot be loaded as config by mistake.
BACKUP=$(mktemp -d "$HOME/.local/state/omarchy-snap-backup.XXXXXXXX" 2>/dev/null) || {
  mkdir -p "$HOME/.local/state"
  BACKUP=$(mktemp -d "$HOME/.local/state/omarchy-snap-backup.XXXXXXXX")
}
backup() {
  local target=$1 relative=${1#"$HOME/"}
  if [[ -e $target || -L $target ]]; then
    mkdir -p "$BACKUP/$(dirname -- "$relative")"
    cp -a -- "$target" "$BACKUP/$relative"
  else
    printf '%s\n' "$relative" >> "$BACKUP/new-files.txt"
  fi
}
echo "Backups: $BACKUP"
backup "$CONFIG"

# hyprpm may reconcile other plugins during update/enable. Always reload the
# user's config on exit, even when installation fails partway through.
trap 'hyprctl reload >/dev/null 2>&1 || true' EXIT

if ! command -v hyprpm >/dev/null; then
  omarchy pkg add hyprpm
fi

# Authenticate explicitly: hyprpm captures its subprocess output, which can
# otherwise hide a sudo prompt. Each operation can drop its sudo timestamp.
sudo -v
hyprpm --no-nix update
if ! python3 - <<'PY'
import pathlib, pwd, sys, tomllib
p = pathlib.Path('/var/cache/hyprpm') / pwd.getpwuid(__import__('os').getuid()).pw_name / 'hypr-edgesnap/state.toml'
try:
    state = tomllib.loads(p.read_text())
except FileNotFoundError:
    sys.exit(1)
sys.exit(0 if 'hypr-edgesnap' in state else 1)
PY
then
  sudo -v
  hyprpm --no-nix add "$URL"
fi
sudo -v
hyprpm --no-nix enable hypr-edgesnap

mkdir -p "$HOME/.local/bin" "$HOME/.config/hypr"
for file in omarchy-window-snap hypr-edgesnap-check; do
  backup "$HOME/.local/bin/$file"
  install -m 755 "$ROOT/payload/$file" "$HOME/.local/bin/$file"
done
for file in edgesnap.lua window-snap.lua; do
  backup "$HOME/.config/hypr/$file"
  install -m 644 "$ROOT/payload/$file" "$HOME/.config/hypr/$file"
done
backup "$HOME/.config/omarchy/hooks/post-update.d/50-hyprpm-rebuild"
omarchy hook install post-update "$ROOT/payload/50-hyprpm-rebuild"
if ! grep -Fqx -- "$LOAD" "$CONFIG"; then
  printf '\n%s\n' "$LOAD" >> "$CONFIG"
fi

hyprctl reload
errors=$(hyprctl configerrors)
[[ -z ${errors//[[:space:]]/} ]] || fail "Config errors after install: $errors. Backups: $BACKUP"
"$HOME/.local/bin/hypr-edgesnap-check" --wait 5
echo
echo "Installed. Drag to edges/corners, or use the snap shortcuts."
echo "Backups: $BACKUP"
echo "See README.md for shortcuts, limitations, and removal."
