#!/usr/bin/env bash
# Local ZMK firmware build via container (zmk-build-arm:stable bundles west + a matching SDK).
# Corne + nice!nano v2 + nice!view, Miryoku (custom_config.h). Outputs uf2 into ./assets/ (gitignored).
#
# Profiles (override via env):
#   Stable (default): ZMK_REF=v0.3.0 BOARD=nice_nano_v2            # reproduces the green CI firmware
#   Bleeding-edge:    ZMK_REF=main   BOARD=nice_nano/nrf52840/zmk  # Zephyr 4.1, HWMv2 board target
#       ZMK Studio: EXTRA="-DCONFIG_ZMK_POINTING=y -DCONFIG_ZMK_STUDIO=y -DSNIPPET=studio-rpc-usb-uart"
#
# Usage: ./build.sh
#        CLEAN=1 ./build.sh                                  # wipe build dirs (after config changes)
#        ZMK_REF=main BOARD=nice_nano/nrf52840/zmk ./build.sh
# NOTE: switching ZMK_REF needs a fresh workspace:  rm -rf "$WORKSPACE"
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- config ----------------------------------------------------------------
ZMK_REMOTE="https://github.com/zmkfirmware/zmk.git"
ZMK_REF="${ZMK_REF:-v0.3.0}"
BOARD="${BOARD:-nice_nano_v2}"
EXTRA="${EXTRA:--DCONFIG_ZMK_POINTING=y}"
WORKSPACE="${WORKSPACE:-${XDG_CACHE_HOME:-$HOME/.cache}/zmk-miryoku}"
IMAGE="${IMAGE:-docker.io/zmkfirmware/zmk-build-arm:stable}"
LEFT_SHIELD="corne_left nice_view_adapter nice_view"
RIGHT_SHIELD="corne_right nice_view_adapter nice_view"
# ---------------------------------------------------------------------------

# Studio needs the &studio_unlock combo, but a CONFIG_ guard in the keymap can't work
# (Zephyr preprocesses devicetree before Kconfig). Load it as an overlay, Studio builds only,
# so config/corne.keymap stays upstream-pristine and the v0.3.0 profile still compiles.
case "$EXTRA" in *CONFIG_ZMK_STUDIO=y*) EXTRA="$EXTRA -DEXTRA_DTC_OVERLAY_FILE=/config/config/studio-unlock.overlay" ;; esac

RUNNER="$(command -v podman || command -v docker)" || { echo "need podman or docker on PATH" >&2; exit 1; }
mkdir -p "$WORKSPACE" "$REPO/assets"
[ "${CLEAN:-0}" = 1 ] && rm -rf "$WORKSPACE/build"

# Everything runs inside the container: repo mounted read-only at /config, workspace at /work.
"$RUNNER" run --rm \
  -v "$REPO":/config:ro \
  -v "$WORKSPACE":/work \
  -e ZMK_REF="$ZMK_REF" -e ZMK_REMOTE="$ZMK_REMOTE" \
  -e BOARD="$BOARD" -e EXTRA="$EXTRA" \
  -e LEFT_SHIELD="$LEFT_SHIELD" -e RIGHT_SHIELD="$RIGHT_SHIELD" \
  -w /work \
  "$IMAGE" bash -euc '
    if [ ! -e zmk/.git ]; then
      git clone --depth 1 -b "$ZMK_REF" "$ZMK_REMOTE" zmk
      ( cd zmk && west init -l app && west update && west zephyr-export )
    fi
    cd zmk/app
    build_half() {
      west build -b "$BOARD" -d "/work/build/$1" -- -DSHIELD="$2" -DZMK_CONFIG=/config/config $EXTRA
      cp "/work/build/$1/zephyr/zmk.uf2" "/work/$1.uf2"
    }
    build_half corne_left  "$LEFT_SHIELD"
    build_half corne_right "$RIGHT_SHIELD"
  '

cp "$WORKSPACE/corne_left.uf2"  "$REPO/assets/corne_left.uf2"
cp "$WORKSPACE/corne_right.uf2" "$REPO/assets/corne_right.uf2"
echo ">> wrote assets/corne_left.uf2 and assets/corne_right.uf2"
echo ">> flash each half: double-tap reset -> NICENANO drive -> drag the matching uf2"
