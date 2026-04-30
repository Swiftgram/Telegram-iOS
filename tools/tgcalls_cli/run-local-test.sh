#!/usr/bin/env bash
# Run N parallel P2P tests locally and report aggregate results.
#
# Usage:
#   ./run-local-test.sh                       # 100 calls, 15s each, 30% loss
#   ./run-local-test.sh -n 1000               # 1000 calls
#   ./run-local-test.sh -n 500 -j 200         # 500 calls, 200 parallel
#   ./run-local-test.sh -n 100 -d 30          # 100 calls, 30s each
#   ./run-local-test.sh --drop-rate 0.5       # 50% loss

set -euo pipefail

BINARY="./bazel-bin/tools/tgcalls_cli/tgcalls_cli"
NUM=100
PARALLEL=150
DURATION=15
DROP_RATE=0.3
DELAY="50-200"
MODE="p2p"
VERSION="13.0.0"

while [[ $# -gt 0 ]]; do
    case $1 in
        -n) NUM="$2"; shift 2 ;;
        -j) PARALLEL="$2"; shift 2 ;;
        -d) DURATION="$2"; shift 2 ;;
        --drop-rate) DROP_RATE="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        *) echo "Usage: $0 [-n NUM] [-j PARALLEL] [-d DURATION] [--drop-rate RATE] [--delay MIN-MAX] [--mode MODE] [--version VER]"; exit 1 ;;
    esac
done

if [ ! -x "$BINARY" ]; then
    echo "Binary not found: $BINARY"
    echo "Run: ./build-input/bazel-8.4.2 build //tools/tgcalls_cli:tgcalls_cli"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Running $NUM calls ($PARALLEL parallel, ${DURATION}s each, drop=${DROP_RATE}, delay=${DELAY}ms, mode=${MODE}, version=${VERSION})"

START=$(date +%s)
launched=0
wave=0

while [ $launched -lt $NUM ]; do
    wave=$((wave + 1))
    remaining=$((NUM - launched))
    batch=$((remaining > PARALLEL ? PARALLEL : remaining))

    pids=()
    for i in $(seq 1 $batch); do
        id=$((launched + i))
        (
            if "$BINARY" --mode "$MODE" --duration "$DURATION" \
                --drop-rate "$DROP_RATE" --delay "$DELAY" --version "$VERSION" --quiet \
                > /dev/null 2>&1; then
                echo "pass" > "$TMPDIR/$id"
            else
                echo "fail" > "$TMPDIR/$id"
            fi
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    launched=$((launched + batch))
    echo "  Wave $wave: $launched/$NUM done"
done

END=$(date +%s)
ELAPSED=$((END - START))

# Tally
success=0
failed=0
for f in "$TMPDIR"/*; do
    [ -f "$f" ] || continue
    if [ "$(cat "$f")" = "pass" ]; then
        success=$((success + 1))
    else
        failed=$((failed + 1))
    fi
done

echo ""
echo "=== Local Mass Test Results ==="
echo "Total:    $NUM"
echo "Success:  $success"
echo "Failed:   $failed"
if [ $NUM -gt 0 ]; then
    rate=$(echo "scale=1; $success * 100 / $NUM" | bc)
    echo "Rate:     ${rate}%"
fi
echo "Duration: ${ELAPSED}s"
echo "Parallel: $PARALLEL"

exit 0
