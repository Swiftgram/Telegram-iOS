#!/usr/bin/env bash
# Launch N tgcalls test tasks on ECS Fargate, spread across reflectors.
#
# Usage:
#   ./run-test.sh                  # 10 tasks, 30s each
#   ./run-test.sh -n 100           # 100 tasks
#   ./run-test.sh -n 50 -d 60     # 50 tasks, 60s each
#   ./run-test.sh --results        # fetch results from last run

set -euo pipefail

CLUSTER="tgcalls-test"
TASK_DEF="tgcalls-test"
REGION="eu-west-1"
SUBNETS="subnet-0292f49f3b4885428,subnet-09b8edab6eb20b837,subnet-0f464b5c62c9a6d1a"
SECURITY_GROUP="sg-0d87a1f19be76c160"
LOG_GROUP="/ecs/tgcalls-test"
REFLECTOR_URL="https://core.telegram.org/getReflectorList"
RUN_FILE="/tmp/tgcalls-last-run.txt"
STATUS_FILE="/tmp/tgcalls-last-status.txt"

NUM_TASKS=10
DURATION=30

usage() {
    echo "Usage: $0 [-n NUM_TASKS] [-d DURATION_SECS] [--results]"
    exit 1
}

fetch_results() {
    if [ ! -f "$RUN_FILE" ]; then
        echo "No run file found. Run a test first."
        exit 1
    fi

    echo "Fetching results from last run..."
    echo ""

    TMPDIR_RESULTS=$(mktemp -d)
    RESULTS_PARALLEL=20
    total=$(wc -l < "$RUN_FILE" | tr -d ' ')
    fetched=0

    # Fetch logs in parallel
    while IFS= read -r task_id; do
        stream="tgcalls/tgcalls/${task_id}"
        (aws logs get-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$stream" \
            --region "$REGION" \
            --query 'events[*].message' \
            --output text > "${TMPDIR_RESULTS}/${task_id}" 2>/dev/null || true) &

        fetched=$((fetched + 1))
        # Throttle: wait every RESULTS_PARALLEL calls
        if [ $((fetched % RESULTS_PARALLEL)) -eq 0 ]; then
            wait
            echo -ne "  Fetched $fetched/$total\r"
        fi
    done < "$RUN_FILE"
    wait
    echo "  Fetched $total/$total"
    echo ""

    # Tally results
    success=0
    fail=0
    errors=""
    no_logs_tasks=()

    for result_file in "${TMPDIR_RESULTS}"/*; do
        [ -f "$result_file" ] || continue
        task_id=$(basename "$result_file")
        output=$(cat "$result_file")

        if [ -z "$output" ]; then
            # No logs yet — queue for retry
            no_logs_tasks+=("$task_id")
        elif echo "$output" | tr '\t' '\n' | grep -q "Audio received:.*yes" && echo "$output" | tr '\t' '\n' | grep -q "Call established:.*yes"; then
            success=$((success + 1))
        else
            fail=$((fail + 1))
            reflector=$(echo "$output" | tr '\t' '\n' | grep -o 'reflector ([^)]*' | sed 's/reflector (//' || echo "unknown")
            errors="${errors}\n  ${task_id}: reflector=${reflector}"
        fi
    done

    rm -rf "$TMPDIR_RESULTS"

    # Retry tasks that had no logs
    if [ ${#no_logs_tasks[@]} -gt 0 ]; then
        echo "Retrying ${#no_logs_tasks[@]} tasks with missing logs..."
        sleep 5
        for task_id in "${no_logs_tasks[@]}"; do
            stream="tgcalls/tgcalls/${task_id}"
            output=$(aws logs get-log-events \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name "$stream" \
                --region "$REGION" \
                --query 'events[*].message' \
                --output text 2>/dev/null || true)

            if [ -n "$output" ] && echo "$output" | tr '\t' '\n' | grep -q "Audio received:.*yes" && echo "$output" | tr '\t' '\n' | grep -q "Call established:.*yes"; then
                success=$((success + 1))
            else
                fail=$((fail + 1))
                ecs_info=""
                if [ -f "$STATUS_FILE" ]; then
                    ecs_info=$(grep "^${task_id}" "$STATUS_FILE" | head -1 | cut -f2-3)
                fi
                if [ -n "$ecs_info" ]; then
                    errors="${errors}\n  ${task_id}: exit=${ecs_info}"
                else
                    errors="${errors}\n  ${task_id} (no logs, no ECS status)"
                fi
            fi
        done
        echo ""
    fi

    echo "=== Test Results ==="
    echo "Total tasks:  $total"
    echo "Success:      $success"
    echo "Failed:       $fail"
    if [ -n "$errors" ]; then
        echo -e "\nFailed tasks:${errors}"
    fi
    exit 0
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        -n) NUM_TASKS="$2"; shift 2 ;;
        -d) DURATION="$2"; shift 2 ;;
        --results) fetch_results ;;
        *) usage ;;
    esac
done

# Fetch reflector list — IPs only (port randomized by CLI)
echo "Fetching reflector list..."
REFLECTOR_CSV=$(curl -s "$REFLECTOR_URL" | cut -d: -f1 | sort -u | tr '\n' ',' | sed 's/,$//')
NUM_REFLECTORS=$(echo "$REFLECTOR_CSV" | tr ',' '\n' | wc -l | tr -d ' ')
echo "Got $NUM_REFLECTORS unique reflector IPs"

# To inject bad addresses for testing, uncomment:
# NUM_BAD=$(( NUM_REFLECTORS / 9 ))
# BAD_CSV=$(for i in $(seq 1 $NUM_BAD); do echo -n "10.255.255.$((i % 256)):1,"; done | sed 's/,$//')
# REFLECTOR_CSV="${REFLECTOR_CSV},${BAD_CSV}"
# echo "Injected $NUM_BAD bad addresses (~10% of pool)"

echo "Launching $NUM_TASKS tasks (${DURATION}s each), each picks a random reflector..."
echo ""

# Clear run files
> "$RUN_FILE"
> "$STATUS_FILE"

# Launch in waves of WAVE_SIZE, waiting for each wave to complete before the next.
# Within each wave, fire PARALLEL API calls concurrently (each launching up to 10 tasks).
WAVE_SIZE=500
PARALLEL=10
TMPDIR_LAUNCH=$(mktemp -d)
remaining=$NUM_TASKS
wave=0

while [ $remaining -gt 0 ]; do
    wave=$((wave + 1))
    wave_target=$((remaining > WAVE_SIZE ? WAVE_SIZE : remaining))
    wave_arns=()
    wave_launched=0

    echo "=== Wave $wave: launching $wave_target tasks ==="

    while [ $wave_launched -lt $wave_target ]; do
        pids=()
        api_calls=0
        for p in $(seq 1 $PARALLEL); do
            left=$((wave_target - wave_launched - api_calls * 10))
            [ $left -le 0 ] && break
            batch=$((left > 10 ? 10 : left))
            outfile="${TMPDIR_LAUNCH}/batch_${wave}_${wave_launched}_${p}"
            api_calls=$((api_calls + 1))

            (aws ecs run-task --region "$REGION" \
                --cluster "$CLUSTER" \
                --task-definition "$TASK_DEF" \
                --launch-type FARGATE \
                --count "$batch" \
                --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=ENABLED}" \
                --overrides "{\"containerOverrides\":[{\"name\":\"tgcalls\",\"command\":[\"--quiet\",\"--reflector-list\",\"${REFLECTOR_CSV}\",\"--duration\",\"${DURATION}\",\"--drop-rate\",\"0.3\",\"--delay\",\"50-200\"]}]}" \
                --query 'tasks[*].taskArn' --output text > "$outfile" 2>&1) &
            pids+=($!)
        done

        for pid in "${pids[@]}"; do
            wait "$pid" 2>/dev/null || true
        done

        for outfile in "${TMPDIR_LAUNCH}"/batch_*; do
            [ -f "$outfile" ] || continue
            while read -r arn; do
                if [[ "$arn" == arn:* ]]; then
                    task_id="${arn##*/}"
                    wave_arns+=("$arn")
                    echo "$task_id" >> "$RUN_FILE"
                    wave_launched=$((wave_launched + 1))
                fi
            done < <(tr '\t' '\n' < "$outfile")
            rm -f "$outfile"
        done

        echo "  Launched $wave_launched/$wave_target in wave $wave"
    done

    remaining=$((remaining - wave_launched))
    echo "  Waiting for wave $wave ($wave_launched tasks) to finish..."

    # Wait in batches of 100
    for ((start=0; start<${#wave_arns[@]}; start+=100)); do
        batch=("${wave_arns[@]:$start:100}")
        aws ecs wait tasks-stopped \
            --cluster "$CLUSTER" \
            --tasks "${batch[@]}" \
            --region "$REGION" 2>/dev/null || true
    done

    # Collect ECS task status while data is fresh (expires after ~1hr)
    echo "  Collecting task status for wave $wave..."
    for ((start=0; start<${#wave_arns[@]}; start+=100)); do
        batch=("${wave_arns[@]:$start:100}")
        aws ecs describe-tasks --cluster "$CLUSTER" --tasks "${batch[@]}" --region "$REGION" \
            --query 'tasks[*].[containers[0].taskArn,containers[0].exitCode,stoppedReason]' \
            --output text 2>/dev/null | while IFS=$'\t' read -r arn exit_code reason; do
            task_id="${arn##*/}"
            echo -e "${task_id}\t${exit_code}\t${reason}" >> "$STATUS_FILE"
        done
    done

    echo "  Wave $wave complete."
    echo ""
done

rm -rf "$TMPDIR_LAUNCH"
total_launched=$(wc -l < "$RUN_FILE" | tr -d ' ')

echo "Launched $total_launched/$NUM_TASKS total tasks."
echo "Run '$0 --results' to see results."
