#!/usr/bin/env bash
# tests/predicate-drift.sh — the drift control for the `drv=` predicate this layer DUPLICATES
# from its producer (opencharly/layer-cuda#34, item 3).
#
# Why this exists: `cdi-no-baked-driver-libs` in this candy carries a byte-identical copy of the
# producer's `drv=` assignment on purpose — a build context cannot reach into another repo's plan.
# The source comments promise that "`diff` of the two blocks is the drift control", but nothing
# ran that diff: change one side and the two predicates silently disagree, the consumer asserting
# a set the producer stopped stripping.
#
# Usage:
#   tests/predicate-drift.sh                 # compare against $LAYER_CUDA_DIR, else a sibling
#                                            # ../../layer-cuda, else SKIP visibly
#   LAYER_CUDA_DIR=<path> tests/predicate-drift.sh
#   tests/predicate-drift.sh --self-test     # three arms: identical OK, drifted FAIL, absent SKIP
#
# The control runs where BOTH trees are checked out (the umbrella working set) — it cannot run
# inside an image build, whose context holds this repo only, and it never fakes that by passing.
set -uo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
mine="$here/charly.yml"

# extract_drv <file> — the full `drv=` assignment, line continuations included. Anchored on the
# ASSIGNMENT: a comment that merely mentions `drv=` is not the predicate.
extract_drv() {
    awk '
        /^[ \t]*drv="/ { inside = 1 }
        inside {
            print
            if ($0 !~ /\\[ \t]*$/) { exit }
        }
    ' "$1"
}

drv_mine=$(extract_drv "$mine")
if [ -z "$drv_mine" ]; then
    echo "FAIL: no \`drv=\"\` assignment found in $mine — the predicate moved and this control is blind" >&2
    exit 1
fi

if [ "${1:-}" = "--self-test" ]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/layer-cuda"

    # arm 1 — an IDENTICAL predicate passes
    printf '%s\n' "$drv_mine" > "$tmp/layer-cuda/charly.yml"
    if ! out=$(LAYER_CUDA_DIR="$tmp/layer-cuda" "$0" 2>&1); then
        echo "FAIL: an identical predicate did not pass: $out" >&2
        exit 1
    fi
    printf '%s\n' "$out" | grep -q '^OK:' || { echo "FAIL: the pass line is not named OK" >&2; exit 1; }

    # arm 2 — a ONE-TOKEN drift fails and names itself
    sed '1s/libcuda\.so\*/libcuda.so/' <<< "$drv_mine" > "$tmp/layer-cuda/charly.yml"
    if [ "$(extract_drv "$tmp/layer-cuda/charly.yml")" = "$drv_mine" ]; then
        echo "FAIL: the self-test mutation changed nothing" >&2
        exit 1
    fi
    if out=$(LAYER_CUDA_DIR="$tmp/layer-cuda" "$0" 2>&1); then
        echo "FAIL: a drifted predicate PASSED the control" >&2
        exit 1
    fi
    printf '%s\n' "$out" | grep -q 'DRIFT' || { echo "FAIL: the refusal does not name the drift" >&2; exit 1; }

    # arm 3 — no producer checkout is a VISIBLE skip, not a silent pass
    out=$(LAYER_CUDA_DIR="$tmp/absent" "$0" 2>&1)
    rc=$?
    [ $rc -eq 0 ] || { echo "FAIL: an absent producer is not a skip (exit $rc)" >&2; exit 1; }
    printf '%s\n' "$out" | grep -q '^SKIP:' || { echo "FAIL: the skip line is not named SKIP" >&2; exit 1; }

    echo "self-test: OK (identical passes, a one-token drift fails naming DRIFT, an absent producer SKIPs visibly)"
    exit 0
fi

producer="${LAYER_CUDA_DIR:-}"
if [ -z "$producer" ] || [ ! -f "$producer/charly.yml" ]; then
    producer=""
    for cand in "$here/../layer-cuda" "$here/../../layer-cuda"; do
        [ -f "$cand/charly.yml" ] && producer=$cand && break
    done
fi
if [ -z "$producer" ]; then
    echo "SKIP: no producer checkout to compare against (set LAYER_CUDA_DIR=<layer-cuda checkout>)"
    echo "SKIP: this control runs where BOTH trees exist — an image build context holds this repo only"
    exit 0
fi

drv_producer=$(extract_drv "$producer/charly.yml")
if [ -z "$drv_producer" ]; then
    echo "FAIL: no \`drv=\"\` assignment found in $producer/charly.yml — the producer moved its predicate" >&2
    exit 1
fi

if ! diff -u <(printf '%s\n' "$drv_producer") <(printf '%s\n' "$drv_mine"); then
    echo "DRIFT: this layer's \`drv=\` no longer matches the producer's ($producer/charly.yml)." >&2
    echo "DRIFT: change BOTH sides in the same cutover, and move the \`require:\` tag with them." >&2
    exit 1
fi

echo "OK: this layer's \`drv=\` is byte-identical to the producer's ($producer/charly.yml)"
