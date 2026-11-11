#!/usr/bin/env bash
# Run as your desktop user, in a terminal inside an Omarchy Hyprland session.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$ROOT/lib.sh"
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

check_prerequisites
for file in "${PAYLOAD[@]}"; do
  [[ -f "$ROOT/payload/$file" ]] || fail "Missing payload/$file; keep the whole repository together."
done

echo "Prerequisites OK. Omarchy $(omarchy-version), Hyprland $(hyprctl -j version | jq -r '.version // .tag // .commit')."
[[ $MODE != --check ]] || exit 0

cat <<INFO

This installs the third-party hypr-edgesnap compositor plugin through hyprpm,
pinned to reviewed commit ${PIN:0:12}. Plugins run inside Hyprland; builds
depend on your Hyprland version and can fail if upstream has not added support
yet. Internet access and sudo are needed.

It adds Super+Alt+arrows and Super+Shift+Home/Page Up/End/Page Down,
replacing any existing actions on those keys, and turns on Hyprland's built-in
floating-window edge alignment (general:snap). Other bindings, monitor
settings, and your gap sizes are left alone. Replaced files are backed up, and
a failed install puts your previous files back.
INFO
read -r -p "Install snapping? [y/N] " answer
[[ $answer == y || $answer == Y || $answer == yes ]] || exit 0

# Keep backups outside ~/.config so they cannot be loaded as config by mistake.
mkdir -p "$HOME/.local/state"
BACKUP=$(mktemp -d "$HOME/.local/state/omarchy-snap-backup.XXXXXXXX")
TARGETS=("$CONFIG")
for file in "${PAYLOAD[@]}"; do TARGETS+=("$(target_for "$file")"); done
for target in "${TARGETS[@]}"; do
  relative=${target#"$HOME/"}
  if [[ -e $target || -L $target ]]; then
    mkdir -p "$BACKUP/$(dirname -- "$relative")"
    cp -a -- "$target" "$BACKUP/$relative"
  else
    printf '%s\n' "$relative" >> "$BACKUP/new-files.txt"
  fi
done
echo "Backups: $BACKUP"

# Put every file back as it was before this run.
rollback() {
  echo "Installation failed; restoring your previous files from $BACKUP" >&2
  local target relative
  for target in "${TARGETS[@]}"; do
    relative=${target#"$HOME/"}
    if [[ -e $BACKUP/$relative || -L $BACKUP/$relative ]]; then
      rm -f -- "$target"
      cp -a -- "$BACKUP/$relative" "$target"
    elif grep -Fqx -- "$relative" "$BACKUP/new-files.txt" 2>/dev/null; then
      rm -f -- "$target"
    fi
  done
  echo "hyprpm may still list hypr-edgesnap; run uninstall.sh to remove it too." >&2
}

CHANGED=false
INSTALLED=false
# hyprpm may reconcile other plugins during update/enable, so always reload
# the user's config on exit, even when installation fails partway through.
on_exit() {
  if $CHANGED && ! $INSTALLED; then rollback; fi
  hyprctl reload >/dev/null 2>&1 || true
}
trap on_exit EXIT

if ! command -v hyprpm >/dev/null; then
  omarchy pkg add hyprpm
fi

# Authenticate explicitly: hyprpm captures its subprocess output, which can
# otherwise hide a sudo prompt. Each operation can drop its sudo timestamp.
sudo -v
hyprpm --no-nix update

# Re-register the plugin if it was added earlier without this pin.
if rev=$(registered_rev); then
  if [[ $rev != "$PIN" ]]; then
    echo
    echo "hypr-edgesnap is registered at ${rev:-the latest upstream commit}, not the reviewed commit."
    echo "It will be removed and added again at ${PIN:0:12}; hyprpm asks you to confirm."
    sudo -v
    hyprpm --no-nix remove hypr-edgesnap
    ! registered_rev >/dev/null || fail "hypr-edgesnap is still registered; it was not re-pinned."
  fi
fi
if ! registered_rev >/dev/null; then
  sudo -v
  hyprpm --no-nix add "$URL" "$PIN"
fi
[[ $(registered_rev) == "$PIN" ]] || fail "hyprpm did not register hypr-edgesnap at $PIN."
sudo -v
hyprpm --no-nix enable hypr-edgesnap

CHANGED=true
for file in "${PAYLOAD[@]}"; do
  target=$(target_for "$file")
  mkdir -p "$(dirname -- "$target")"
  install -m "$(mode_for "$file")" "$ROOT/payload/$file" "$target"
done
if ! grep -Fqx -- "$LOAD" "$CONFIG"; then
  printf '\n%s\n' "$LOAD" >> "$CONFIG"
fi

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
[[ -z ${errors//[[:space:]]/} ]] || fail "Config errors after install: $errors"
INSTALLED=true

echo
if "$HOME/.local/bin/hypr-edgesnap-check" --wait 5; then
  echo "Installed. Drag to edges/corners, or use the snap shortcuts."
else
  echo "Installed, but drag snapping is not active yet (see the message above)."
  echo "Keyboard snapping uses the standalone helper until the plugin loads."
fi
echo "Backups: $BACKUP"
echo "See README.md for shortcuts, settings, and removal (bash uninstall.sh)."
