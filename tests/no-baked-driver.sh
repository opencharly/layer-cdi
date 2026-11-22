#!/usr/bin/env bash
# tests/no-baked-driver.sh — the executable control for this layer's two "nothing baked" steps
# (opencharly/layer-cuda#34).
#
# The steps assert a NEGATIVE: no host-coupled driver user-space and no nvidia* binary is baked.
# Reading the predicate cannot prove either, and a predicate widened or narrowed in a later edit
# reads just as plausible as the correct one. This fixture EXECUTES both step bodies — they are
# overridable for exactly this purpose (CDI_LIB_DIRS / CDI_BIN_DIRS) — against synthetic layouts:
#
#   clean    the CUDA runtime and an ordinary binary are present -> both steps PASS (rc=0)
#   planted  a driver library, a vdpau twin, the xorg driver and nvidia-smi are present
#            -> BOTH steps FAIL, so neither assertion can stop seeing a surface
#
# The clean arm is the false-positive control: a predicate that reds on libcudart would fail it.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
candy="$here/charly.yml"
[ -f "$candy" ] || { echo "FAIL: $candy not found" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

extract() {  # extract <step-id> <out-file>
    awk -v id="$1" '
      $0 ~ ("id: " id "$") { on=1 }
      on && /command: \|/ { body=1; next }
      body && /^            - / { exit }
      body { sub(/^                /, ""); print }
    ' "$candy" > "$2"
    [ -s "$2" ] || { echo "FAIL: the step body for $1 was not extracted" >&2; exit 1; }
}

libs_body="$work/libs.sh"; bins_body="$work/bins.sh"
extract cdi-no-baked-driver-libs "$libs_body"
extract cdi-no-baked-driver-binaries "$bins_body"
grep -q 'libcuda\.so\*' "$libs_body" || { echo "FAIL: the libs step body looks wrong" >&2; exit 1; }

seed_clean() {  # seed_clean <root>
    mkdir -p "$1/lib" "$1/bin"
    for f in libcudart.so.13 libcudart_static.a libcublas.so.13; do : > "$1/lib/$f"; done
    : > "$1/bin/ffmpeg"
}

plant_driver() {  # plant_driver <root>
    : > "$1/lib/libcuda.so.1"
    : > "$1/lib/libnvidia-ml.so.1"
    mkdir -p "$1/lib/vdpau" "$1/lib/xorg/modules/drivers"
    : > "$1/lib/vdpau/libvdpau_nvidia.so.1"
    : > "$1/lib/xorg/modules/drivers/nvidia_drv.so"
    : > "$1/bin/nvidia-smi"
}

fail=0

# --- arm 1: a clean image passes both steps (the false-positive control) -------------------
root="$work/clean"; seed_clean "$root"
if out=$(env CDI_LIB_DIRS="$root/lib" CDI_BIN_DIRS="$root/bin" bash "$libs_body" 2>&1); then rc=0; else rc=$?; fi
printf 'clean libs arm (rc=%s):\n%s\n' "$rc" "$out" | sed 's/^/  /'
[ "$rc" -eq 0 ] || { echo "FAIL: the libs assertion reds on a clean image (it counted the CUDA runtime)" >&2; fail=1; }
if out=$(env CDI_LIB_DIRS="$root/lib" CDI_BIN_DIRS="$root/bin" bash "$bins_body" 2>&1); then rc=0; else rc=$?; fi
printf 'clean bins arm (rc=%s):\n%s\n' "$rc" "$out" | sed 's/^/  /'
[ "$rc" -eq 0 ] || { echo "FAIL: the bins assertion reds on a clean image" >&2; fail=1; }

# --- arm 2: a planted driver fails BOTH steps ----------------------------------------------
root="$work/planted"; seed_clean "$root"; plant_driver "$root"
if out=$(env CDI_LIB_DIRS="$root/lib" CDI_BIN_DIRS="$root/bin" bash "$libs_body" 2>&1); then rc=0; else rc=$?; fi
printf 'planted libs arm (rc=%s):\n%s\n' "$rc" "$out" | sed 's/^/  /'
[ "$rc" -ne 0 ] || { echo "FAIL: the libs assertion PASSED with a driver library, vdpau twin and xorg driver baked" >&2; fail=1; }
if out=$(env CDI_LIB_DIRS="$root/lib" CDI_BIN_DIRS="$root/bin" bash "$bins_body" 2>&1); then rc=0; else rc=$?; fi
printf 'planted bins arm (rc=%s):\n%s\n' "$rc" "$out" | sed 's/^/  /'
[ "$rc" -ne 0 ] || { echo "FAIL: the bins assertion PASSED with nvidia-smi baked" >&2; fail=1; }

if [ "$fail" -eq 0 ]; then
    echo 'no-baked-driver: both arms behaved (clean passes; a planted driver reds libs AND bins)'
else
    echo 'no-baked-driver: FAILED'
fi
exit "$fail"
