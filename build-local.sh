#!/bin/bash
# build-local.sh — Local Docker-based ZMK build for roBa
# Run from git bash. Requires Docker Desktop running.
#
# Usage:
#   ./build-local.sh              # build all 3 (L, R, settings_reset)
#   ./build-local.sh roBa_L       # single target
#
# First run: ~10-15 min (fetches ZMK deps into docker volume)
# Subsequent runs: ~30-60 sec per target
set -e

WORKSPACE_VOL="zmk-workspace"
CONFIG_HOST="/c/Users/tsune/zmk-config-roBa"
OUTPUT_HOST="/c/Users/tsune/roBa-LP/uf2/local"
IMAGE="zmkfirmware/zmk-build-arm:stable"

# Common docker args (workspace vol + rock's config bind mount + fork root for EXTRA_MODULES)
DOCKER_MOUNTS=(
    -v "$WORKSPACE_VOL:/workspaces/zmk"
    -v "$CONFIG_HOST/config:/workspaces/zmk/config"
    -v "$CONFIG_HOST:/workspaces/roba-src:ro"
)
DOCKER_ENV=(
    -e ZEPHYR_BASE=/workspaces/zmk/zephyr
    -e CMAKE_PREFIX_PATH=/workspaces/zmk/zephyr/share/zephyr-package/cmake
)

# First-time init check
NEED_INIT=$(MSYS_NO_PATHCONV=1 docker run --rm -v "$WORKSPACE_VOL:/w" alpine sh -c 'test -d /w/.west && echo no || echo yes' 2>/dev/null || echo yes)
if [ "$NEED_INIT" = "yes" ]; then
    echo "=== First-time: west init + update (~5-10 min for deps) ==="
    MSYS_NO_PATHCONV=1 docker run --rm "${DOCKER_MOUNTS[@]}" -w /workspaces/zmk "$IMAGE" \
        bash -c "west init -l config && west update && west zephyr-export"
    echo "=== Init done ==="
fi

# Target list
if [ $# -eq 0 ]; then
    TARGETS="roBa_L roBa_R settings_reset"
else
    TARGETS="$@"
fi

# Build all targets in a single container invocation (fast)
BUILD_CMDS=""
for target in $TARGETS; do
    BUILD_CMDS+="echo '=== Building $target ===' && west build --pristine=auto -s zmk/app -d build/$target -b seeeduino_xiao_ble -- -DSHIELD=$target -DZMK_CONFIG=/workspaces/zmk/config -DZMK_EXTRA_MODULES=/workspaces/roba-src || exit 1; "
done

MSYS_NO_PATHCONV=1 docker run --rm "${DOCKER_MOUNTS[@]}" "${DOCKER_ENV[@]}" -w /workspaces/zmk "$IMAGE" \
    bash -c "$BUILD_CMDS"

# Copy uf2 out
mkdir -p "$OUTPUT_HOST"
COPY_CMDS=""
for target in $TARGETS; do
    COPY_CMDS+="cp /workspaces/zmk/build/$target/zephyr/zmk.uf2 /output/$target-seeeduino_xiao_ble-zmk.uf2; "
done
MSYS_NO_PATHCONV=1 docker run --rm -v "$WORKSPACE_VOL:/workspaces/zmk" -v "$OUTPUT_HOST:/output" "$IMAGE" \
    bash -c "$COPY_CMDS"

echo ""
echo "=== Done. uf2 files: ==="
ls -lh "$OUTPUT_HOST/"
