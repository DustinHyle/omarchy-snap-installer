# Shared by install.sh and uninstall.sh. Not meant to be run on its own.

CONFIG="$HOME/.config/hypr/hyprland.lua"
LOAD='require("hypr.window-snap") -- omarchy-snap-installer'
URL=https://github.com/LordMelkor/hypr-edgesnap
# Reviewed upstream commit. hyprpm keeps building this exact revision on
# `hyprpm update`, so new upstream code is never pulled in automatically.
# To move to a newer release: review the upstream diff, change this, rerun.
PIN=5232f5105f1c59f986533af132392bcde1865fd9
# First Omarchy release with the o.rebind helper the bindings rely on.
MIN_OMARCHY=4.5.0
OMARCHY_DIR=${OMARCHY_PATH:-/usr/share/omarchy}
PAYLOAD=(edgesnap.lua window-snap.lua omarchy-window-snap hypr-edgesnap-check 50-hyprpm-rebuild)

fail() { echo "Error: $*" >&2; exit 1; }

# Make sure the next sudo call will not prompt. hyprpm captures its own
# output, which can hide a sudo prompt, so authenticate visibly first. `sudo -v`
# alone is not enough: it asks for a password even when sudoers grants
# NOPASSWD, as long as any other rule for the user requires one.
sudo_ready() { sudo -n true 2>/dev/null || sudo -v; }

target_for() {
  case $1 in
    *.lua) echo "$HOME/.config/hypr/$1" ;;
    50-hyprpm-rebuild) echo "$HOME/.config/omarchy/hooks/post-update.d/$1" ;;
    *) echo "$HOME/.local/bin/$1" ;;
  esac
}

mode_for() { [[ $1 == *.lua ]] && echo 644 || echo 755; }

# Prints hypr-edgesnap's pinned revision (empty when unpinned); fails when
# hyprpm has no such repository.
registered_rev() {
  # HYPR_EDGESNAP_HYPRPM_CACHE exists only so tests can point at a fake cache.
  python3 -I - <<'PY'
import os, pathlib, pwd, sys, tomllib
base = os.environ.get('HYPR_EDGESNAP_HYPRPM_CACHE') or pathlib.Path('/var/cache/hyprpm') / pwd.getpwuid(os.getuid()).pw_name
p = pathlib.Path(base) / 'hypr-edgesnap/state.toml'
try:
    state = tomllib.loads(p.read_text())
except (FileNotFoundError, tomllib.TOMLDecodeError):
    sys.exit(1)
if 'hypr-edgesnap' not in state:
    sys.exit(1)
print(state.get('repository', {}).get('rev', ''))
PY
}

check_omarchy_version() {
  local version
  command -v omarchy-version >/dev/null && version=$(omarchy-version 2>/dev/null) || version=""
  local need="Omarchy $MIN_OMARCHY or newer is required"
  case $version in
    "") fail "Cannot determine the Omarchy version. $need; run 'omarchy update' first." ;;
    dev*) ;; # a git checkout has no release number; the helper check below decides
    *)
      (( $(vercmp "${version%-*}" "$MIN_OMARCHY") >= 0 )) ||
        fail "$need (this system has $version). Run 'omarchy update', then try again." ;;
  esac
  grep -q '^function o\.rebind' "$OMARCHY_DIR/default/hypr/helpers.lua" 2>/dev/null ||
    fail "$need: this Omarchy ($version) lacks the Lua config's o.rebind helper. Run 'omarchy update', then try again."
}

check_prerequisites() {
  [[ $EUID != 0 ]] || fail "Run as your regular user, not with sudo."
  local cmd
  for cmd in omarchy hyprctl python3 jq sudo vercmp; do
    command -v "$cmd" >/dev/null || fail "Missing required command: $cmd"
  done
  check_omarchy_version
  [[ -f "$CONFIG" ]] || fail "This installer needs Omarchy's Lua config at $CONFIG."
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || fail "Run inside the target Hyprland desktop session."
  hyprctl -j version >/dev/null || fail "Cannot reach Hyprland."
  local errors
  errors=$(hyprctl configerrors)
  [[ -z ${errors//[[:space:]]/} ]] || fail "Fix existing Hyprland config errors first: $errors"
}
