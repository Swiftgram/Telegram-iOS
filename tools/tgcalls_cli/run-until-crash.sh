#!/usr/bin/env bash
# Run parallel tests, stop on first crash (non-zero exit).
set -euo pipefail

BINARY="./bazel-bin/tools/tgcalls_cli/tgcalls_cli"
PARALLEL=250
DURATION=15
VERSION="11.0.0"
DROP_RATE=0.3
DELAY="50-200"
MODE="p2p"

while [[ $# -gt 0 ]]; do
    case $1 in
        -j) PARALLEL="$2"; shift 2 ;;
        -d) DURATION="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --drop-rate) DROP_RATE="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        *) echo "Usage: $0 [-j PARALLEL] [-d DURATION] [--version VER] [--drop-rate R] [--delay D] [--mode M]"; exit 1 ;;
    esac
done

if [ ! -x "$BINARY" ]; then
    echo "Binary not found: $BINARY"
    exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Running waves of $PARALLEL until first crash (${DURATION}s, drop=${DROP_RATE}, delay=${DELAY}, version=${VERSION})"

wave=0
total=0
while true; do
    wave=$((wave + 1))
    pids=()
    for i in $(seq 1 $PARALLEL); do
        id=$((total + i))
        (
            set +e
            "$BINARY" --mode "$MODE" --duration "$DURATION" \
                --drop-rate "$DROP_RATE" --delay "$DELAY" --version "$VERSION" --quiet \
                > "$TMPDIR/${id}.out" 2>"$TMPDIR/${id}.err"
            echo $? > "$TMPDIR/${id}.rc"
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    total=$((total + PARALLEL))

    # Check for crashes
    crashes=0
    for i in $(seq $((total - PARALLEL + 1)) $total); do
        rc_file="$TMPDIR/${i}.rc"
        if [ ! -f "$rc_file" ]; then
            crashes=$((crashes + 1))
            echo ""
            echo "=== CRASH in run $i (no rc file) ==="
            echo "--- stderr ---"
            cat "$TMPDIR/${i}.err" 2>/dev/null || echo "(empty)"
        else
            rc=$(cat "$rc_file")
            if [ "$rc" -gt 128 ] 2>/dev/null; then
                crashes=$((crashes + 1))
                echo ""
                echo "=== CRASH in run $i (exit $rc) ==="
                echo "--- stderr ---"
                cat "$TMPDIR/${i}.err" 2>/dev/null || echo "(empty)"
                echo "--- stdout ---"
                cat "$TMPDIR/${i}.out" 2>/dev/null || echo "(empty)"
                # Only show first crash in detail
                if [ $crashes -eq 1 ]; then
                    echo "=== END CRASH ==="
                fi
            fi
        fi
    done

    if [ $crashes -gt 0 ]; then
        echo ""
        echo "Wave $wave: $crashes crashes in $PARALLEL runs (total $total runs)"
        exit 1
    fi

    echo "  Wave $wave: $PARALLEL/$PARALLEL passed (total $total)"
done
