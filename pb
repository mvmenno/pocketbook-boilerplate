#!/usr/bin/env sh
# pb - build, deploy and run PocketBook InkView apps.
#
#   ./pb setup              build the toolchain image + fetch InkView SDK headers
#   ./pb build [--debug]    cross-compile into build/ (Release by default)
#   ./pb deploy             copy the app into the pbemu /mnt/ext1/applications
#   ./pb run                build + deploy + launch the app in a running pbemu
#   ./pb log                follow the app's stdout/stderr from the last `run`
#   ./pb install DIR        copy the app to a USB-mounted device (DIR = its root)
#   ./pb shell              interactive shell inside the toolchain container
#   ./pb clean              remove build/
#
# Environment:
#   PB_FIRMWARE   staged firmware dir (default: the single one in $PBEMU_DIR)
#   PBEMU_DIR     pbemu checkout (default: ../pbemu)
#   PODMAN        container runtime (default: podman, falls back to docker)
#   PB_CONTAINER  running pbemu container name (default: pb-pocketbook-ui)

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
IMAGE=pocketbook-sdk
APP=hello_world.app
BUILD_DIR="$ROOT/build"

# Official headers: github.com/pocketbook/SDK_6.3.0, branch 6.5 (pinned).
SDK_REPO=https://github.com/pocketbook/SDK_6.3.0
SDK_COMMIT=dd8de463733a2bc0d53d1214b64734586fac427e
SDK_HDR_PATH=SDK-B288/usr/arm-obreey-linux-gnueabi/sysroot/usr/local/include

PBEMU_DIR="${PBEMU_DIR:-$ROOT/../pbemu}"
PB_CONTAINER="${PB_CONTAINER:-pb-pocketbook-ui}"
if [ -z "${PODMAN:-}" ]; then
    if command -v podman >/dev/null 2>&1; then PODMAN=podman; else PODMAN=docker; fi
fi

die() { printf 'pb: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

find_firmware() {
    if [ -n "${PB_FIRMWARE:-}" ]; then
        FW="$(CDPATH= cd -- "$PB_FIRMWARE" && pwd)" || die "PB_FIRMWARE not found: $PB_FIRMWARE"
    else
        FW=""
        n=0
        for d in "$PBEMU_DIR"/*/; do
            [ -e "$d/ebrmain/lib/libinkview.so" ] || continue
            FW="$(CDPATH= cd -- "$d" && pwd)"
            n=$((n + 1))
        done
        [ "$n" -eq 1 ] || die "found $n staged firmwares in $PBEMU_DIR; set PB_FIRMWARE=<dir>"
    fi
    [ -e "$FW/ebrmain/lib/libinkview.so" ] || die "$FW does not look like a staged firmware (no ebrmain/lib/libinkview.so)"
}

container() {
    # Run a command in the toolchain image with the project and firmware mounted.
    find_firmware
    if [ "$PODMAN" = podman ]; then
        user_args="--userns=keep-id"
    else
        user_args="-u $(id -u):$(id -g)"
    fi
    tty_args=""
    [ -t 0 ] && tty_args="-it"
    # shellcheck disable=SC2086
    "$PODMAN" run --rm $tty_args $user_args \
        -v "$ROOT:/src:z" \
        -v "$FW:/firmware:ro,z" \
        -e PB_FIRMWARE_ROOT=/firmware \
        -w /src "$IMAGE" "$@"
}

cmd_setup() {
    info "building container image '$IMAGE'"
    "$PODMAN" build -t "$IMAGE" -f "$ROOT/Containerfile" "$ROOT"

    if [ -f "$ROOT/sdk/include/inkview.h" ]; then
        info "SDK headers already present in sdk/include"
    else
        info "fetching InkView SDK headers ($SDK_REPO @ ${SDK_COMMIT%"${SDK_COMMIT#???????}"})"
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        git -C "$tmp" init -q
        git -C "$tmp" remote add origin "$SDK_REPO"
        git -C "$tmp" sparse-checkout set --no-cone "/$SDK_HDR_PATH/*.h"
        git -C "$tmp" fetch -q --depth 1 --filter=blob:none origin "$SDK_COMMIT"
        git -C "$tmp" checkout -q FETCH_HEAD
        mkdir -p "$ROOT/sdk/include"
        cp "$tmp/$SDK_HDR_PATH"/*.h "$ROOT/sdk/include/"
    fi
    find_firmware
    info "firmware: $FW"
}

cmd_build() {
    type=Release
    [ "${1:-}" = "--debug" ] && type=Debug
    "$PODMAN" image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' missing - run ./pb setup"
    container sh -c "
        cmake -S . -B build -G Ninja \
            -DCMAKE_TOOLCHAIN_FILE=cmake/pocketbook-toolchain.cmake \
            -DCMAKE_BUILD_TYPE=$type \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null &&
        cmake --build build &&
        file build/$APP"
}

cmd_deploy() {
    find_firmware
    [ -f "$BUILD_DIR/$APP" ] || die "build/$APP not found - run ./pb build"
    dest="$FW/.live/mnt/ext1/applications"
    [ -d "$FW/.live/mnt/ext1" ] || die "$FW/.live not found - start the emulator once (pbemu start)"
    mkdir -p "$dest"
    cp "$BUILD_DIR/$APP" "$dest/$APP"
    chmod 755 "$dest/$APP"
    info "deployed to $dest/$APP (emulator: /mnt/ext1/applications/$APP)"
}

cmd_run() {
    cmd_build
    cmd_deploy
    "$PODMAN" container inspect "$PB_CONTAINER" >/dev/null 2>&1 \
        || die "emulator container '$PB_CONTAINER' is not running - start it with: $PBEMU_DIR/pbemu start"
    # /tmp inside the emulator is $FW/.live/tmp on the host.
    cp "$BUILD_DIR/pb-launch" "$FW/.live/tmp/pb-launch"
    fw=/workspace/firmware
    # Same guest environment pbemu uses (tools/pbemu/run/launch.py).
    env="-E LANG=en_US.utf8 -E LC_ALL=en_US.utf8 -E HOME=/tmp \
        -E XDG_RUNTIME_DIR=/tmp/runtime-pocketbook \
        -E PATH=/ebrmain/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        -E PB_POCKETBOOK_FIRMWARE_ROOT=$fw -E PB_DEVICE_STAGE_ROOT=$fw/.live \
        -E PB_ARM_USE_FB_STUB=1 -E ALSA_CONFIG_PATH=/etc/asound.conf \
        -E LD_PRELOAD=/workspace/src/shim/build-arm/libshim.so"
    app="/mnt/ext1/applications/$APP"
    info "launching $APP in emulator"
    # Stop a previous instance so the freshly built binary is what runs.
    "$PODMAN" exec "$PB_CONTAINER" sh -c "pkill -f ' $app\$' && sleep 1" || true
    "$PODMAN" exec "$PB_CONTAINER" sh -lc "qemu-arm -L $fw/.live/guest $env /tmp/pb-launch $app" 2>&1 \
        | grep '^task=' || die "launch failed - see ./pb log"
    info "app output: ./pb log"
}

cmd_log() {
    find_firmware
    log="$FW/.live/var/log/monitor.log"
    [ -f "$log" ] || die "no log at $log"
    info "following $log (apps launched by monitor.app log here)"
    tail -n 50 -f "$log"
}

cmd_install() {
    dir="${1:-}"
    [ -n "$dir" ] && [ -d "$dir" ] || die "usage: ./pb install /run/media/\$USER/<PocketBook>"
    [ -f "$BUILD_DIR/$APP" ] || die "build/$APP not found - run ./pb build"
    mkdir -p "$dir/applications"
    cp "$BUILD_DIR/$APP" "$dir/applications/$APP"
    sync
    info "installed to $dir/applications/$APP - eject the device, then open it from Applications"
}

case "${1:-}" in
    setup)   shift; cmd_setup "$@" ;;
    build)   shift; cmd_build "$@" ;;
    deploy)  shift; cmd_deploy "$@" ;;
    run)     shift; cmd_run "$@" ;;
    log)     shift; cmd_log "$@" ;;
    install) shift; cmd_install "$@" ;;
    shell)   shift; container bash ;;
    clean)   rm -rf "$BUILD_DIR" ;;
    *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
