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

# hyprpm calls `sudo -k` after each operation. Scope a shim to installer child
# commands only: defer that invalidation until cleanup, and forward every real
# privileged command to the real sudo in noninteractive mode. No password is
# read/stored by us, no sudoers changes, and builds still run as the user.
start_sudo_session() {
  SUDO_REAL=$(command -v sudo)
  SUDO_SESSION_DIR=$(mktemp -d)
  chmod 700 "$SUDO_SESSION_DIR"
  {
    echo '#!/usr/bin/env bash'
    echo 'if [[ $# == 1 && $1 == -k ]]; then exit 0; fi'
    printf 'exec %q -n "$@"\n' "$SUDO_REAL"
  } > "$SUDO_SESSION_DIR/sudo"
  chmod 755 "$SUDO_SESSION_DIR/sudo"
  "$SUDO_REAL" -n true 2>/dev/null || "$SUDO_REAL" -v || return
  "$SUDO_REAL" -n true || {
    echo 'sudo did not cache authorization; check its timestamp policy before retrying.' >&2
    return 1
  }
  (
    while sleep 30; do
      "$SUDO_REAL" -n -v >/dev/null 2>&1 || exit
    done
  ) </dev/null >/dev/null 2>&1 &
  SUDO_KEEPALIVE=$!
}

session_run() { PATH="$SUDO_SESSION_DIR:$PATH" "$@"; }
hyprpm_run() { session_run hyprpm "$@"; }

stop_sudo_session() {
  if [[ -n ${SUDO_KEEPALIVE:-} ]]; then
    kill "$SUDO_KEEPALIVE" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE" 2>/dev/null || true
  fi
  if [[ -n ${SUDO_SESSION_DIR:-} ]]; then
    rm -f -- "$SUDO_SESSION_DIR/sudo"
    rmdir -- "$SUDO_SESSION_DIR" || true
    "$SUDO_REAL" -k || true
  fi
}

plugin_cache() {
  python3 -I - <<'PY'
import os, pathlib, pwd
print(os.environ.get('HYPR_EDGESNAP_HYPRPM_CACHE') or pathlib.Path('/var/cache/hyprpm') / pwd.getpwuid(os.getuid()).pw_name)
PY
}

# Capture after the initial update, before replacing the registration. These
# are the actual built files, so recovery does not need GitHub or a rebuild.
snapshot_plugin() {
  PLUGIN_CACHE=$(plugin_cache)
  PLUGIN_SNAPSHOT="$BACKUP/plugin-before-replacement"
  mkdir -m 700 "$PLUGIN_SNAPSHOT"
  PLUGIN_EXISTED=false
  PLUGIN_WAS_LOADED=false
  if registered_rev >/dev/null; then
    local repo="$PLUGIN_CACHE/hypr-edgesnap"
    [[ -f $repo/state.toml && ! -L $repo/state.toml && -f $repo/hypr-edgesnap.so && ! -L $repo/hypr-edgesnap.so ]] ||
      fail 'Cannot safely snapshot the existing hypr-edgesnap cache; no replacement attempted.'
    cp -- "$repo/state.toml" "$repo/hypr-edgesnap.so" "$PLUGIN_SNAPSHOT/"
    PLUGIN_EXISTED=true
    if hyprctl -j plugin list | jq -e 'any(.[]; .name == "hypr-edgesnap")' >/dev/null; then
      PLUGIN_WAS_LOADED=true
    fi
  fi
}

restore_plugin() {
  echo 'Restoring the previous hypr-edgesnap registration and built plugin.' >&2
  local repo="$PLUGIN_CACHE/hypr-edgesnap"
  hyprctl plugin unload "$repo/hypr-edgesnap.so" >/dev/null 2>&1 || true
  if $PLUGIN_EXISTED; then
    session_run sudo install -d -m 755 -- "$repo" || return
    session_run sudo install -m 644 -o 0 -g 0 -- "$PLUGIN_SNAPSHOT/state.toml" "$repo/state.toml" || return
    session_run sudo install -m 755 -o 0 -g 0 -- "$PLUGIN_SNAPSHOT/hypr-edgesnap.so" "$repo/hypr-edgesnap.so" || return
    if $PLUGIN_WAS_LOADED; then
      hyprctl plugin load "$repo/hypr-edgesnap.so" || return
    fi
  elif registered_rev >/dev/null; then
    # Recovery of a fresh install restores the previous absence of this repo.
    printf 'y\n' | hyprpm_run --no-nix remove hypr-edgesnap || return
    ! registered_rev >/dev/null || return 1
  fi
}

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
