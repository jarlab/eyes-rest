#!/usr/bin/env bash
# Builds build/EyeRest.app from the SwiftPM package, then optionally installs and opens it.
# Works from any directory; run with --help for the options.
set -euo pipefail

readonly APP_NAME="EyeRest"

# CDPATH is ignored and cd's output discarded: with CDPATH set, cd prints the directory, which would end up in ROOT.
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
readonly ROOT
readonly BUILD_DIR="$ROOT/build"
readonly APP="$BUILD_DIR/$APP_NAME.app"
readonly PLIST_SOURCE="$ROOT/Resources/Info.plist"
readonly ICON_SCRIPT="$ROOT/scripts/make-icon.swift"
readonly ICNS="$BUILD_DIR/AppIcon.icns"

log() { printf '==> %s\n' "$*"; }
die() { printf 'build-app: error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: scripts/build-app.sh [--install [--system]] [--open]

  (no options)  build, assemble and ad-hoc sign build/EyeRest.app
  --install     quit a running EyeRest and copy the app to ~/Applications
  --system      with --install: copy to /Applications instead (needs an administrator account)
  --open        quit a running EyeRest, then open the built (or installed) app

Environment:
  EYEREST_VERSION  CFBundleShortVersionString (default: the value in Resources/Info.plist)
  EYEREST_BUILD    CFBundleVersion (default: the git commit count, else the value in Info.plist)
EOF
}

# Temporary icon work and install staging directories, removed on exit.
icon_work=""
stage_dir=""
cleanup() {
    if [[ -n "$icon_work" ]]; then rm -rf "$icon_work"; fi
    if [[ -n "$stage_dir" ]]; then rm -rf "$stage_dir"; fi
}
trap cleanup EXIT

# Quits a running EyeRest of the current user and waits up to 3 s for it to exit. Uses signals,
# not osascript, which would trigger an Automation permission prompt.
stop_running_app() {
    local uid
    uid="$(id -u)"
    pgrep -x -u "$uid" "$APP_NAME" >/dev/null || return 0
    log "Quitting the running $APP_NAME"
    pkill -x -u "$uid" "$APP_NAME" || true
    for _ in $(seq 1 30); do
        pgrep -x -u "$uid" "$APP_NAME" >/dev/null || return 0
        sleep 0.1
    done
    die "$APP_NAME is still running; quit it from its menu-bar icon and try again"
}

install=false
system=false
open_app=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) install=true ;;
        --system) system=true ;;
        --open) open_app=true ;;
        -h | --help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done
if $system && ! $install; then
    die "--system only applies together with --install"
fi

for tool in swift plutil iconutil codesign ditto; do
    command -v "$tool" >/dev/null 2>&1 ||
        die "'$tool' not found; install the Xcode Command Line Tools with: xcode-select --install"
done
[[ -f "$PLIST_SOURCE" ]] || die "missing $PLIST_SOURCE"

cd "$ROOT" || die "cannot enter $ROOT"

# 1. Release binary.
log "Building the release binary"
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
binary="$bin_dir/$APP_NAME"
[[ -f "$binary" && -x "$binary" ]] || die "release binary not found at $binary (did 'swift build -c release' succeed?)"

# 2. Bundle skeleton, executable and Info.plist.
log "Assembling ${APP#"$ROOT/"}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$binary" "$APP/Contents/MacOS/$APP_NAME"

plist="$APP/Contents/Info.plist"
cp "$PLIST_SOURCE" "$plist"
version="${EYEREST_VERSION:-}"
if [[ -z "$version" ]]; then
    version="$(plutil -extract CFBundleShortVersionString raw "$PLIST_SOURCE")"
fi
build_number="${EYEREST_BUILD:-}"
if [[ -z "$build_number" ]]; then
    build_number="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null ||
        plutil -extract CFBundleVersion raw "$PLIST_SOURCE")"
fi
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build_number" "$plist"
plutil -lint -s "$plist"

# 3. App icon, re-rendered only when make-icon.swift is newer than the cached icns.
if [[ ! -f "$ICNS" || "$ICON_SCRIPT" -nt "$ICNS" ]]; then
    log "Rendering the app icon"
    mkdir -p "$BUILD_DIR"
    icon_work="$(mktemp -d "$BUILD_DIR/icon.XXXXXX")"
    swift "$ICON_SCRIPT" "$icon_work/AppIcon.iconset"
    iconutil -c icns "$icon_work/AppIcon.iconset" -o "$icon_work/AppIcon.icns"
    mv -f "$icon_work/AppIcon.icns" "$ICNS"
else
    log "Using the cached app icon"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# 4. Sign last: any change to the bundle after this point would break the seal.
log "Signing (ad hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"
log "Built $APP_NAME $version ($build_number): $APP"

launch_target="$APP"

if $install; then
    if $system; then dest_dir="/Applications"; else dest_dir="$HOME/Applications"; fi
    dest="$dest_dir/$APP_NAME.app"
    # Everything that can fail for lack of permission happens before the running EyeRest is quit, so a failed
    # install never leaves the user without it.
    mkdir -p "$dest_dir" 2>/dev/null || true
    if [[ ! -w "$dest_dir" ]]; then
        if $system; then die "cannot write to $dest_dir; installing there needs an administrator account"; fi
        die "cannot write to $dest_dir"
    fi
    stage_dir="$(mktemp -d "$dest_dir/.$APP_NAME-install.XXXXXX")"
    ditto "$APP" "$stage_dir/$APP_NAME.app"
    stop_running_app
    log "Installing to $dest"
    # Renaming the old copy within its folder works whoever owns it; deleting it might not.
    retired="$dest_dir/.$APP_NAME-previous.$$"
    if [[ -e "$dest" ]]; then mv "$dest" "$retired"; fi
    mv "$stage_dir/$APP_NAME.app" "$dest"
    if [[ -e "$retired" ]]; then
        rm -rf "$retired" 2>/dev/null || log "Could not delete the previous copy; remove $retired by hand"
    fi
    codesign --verify --strict "$dest"
    launch_target="$dest"
fi

if $open_app; then
    stop_running_app
    log "Opening $launch_target"
    open "$launch_target"
fi
