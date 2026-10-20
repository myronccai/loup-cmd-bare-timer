#!/usr/bin/env bash
# Boot tests: boot the kernel under QEMU, wait for lines on its serial port,
# press keys, and compare the transcript and QEMU's exit status with the
# expected ones.
#
# Each case is a list of steps: `wait:TEXT` waits (up to STEP_TIMEOUT
# seconds) until TEXT appears in the output, `send:KEYS` types KEYS. In
# transcripts, instruction addresses (`rip 0x...`, `pc 0x...`) and the tick
# count at quit time are replaced by N, since they differ between builds and
# runs, and heartbeats after the third are dropped (a slow machine may print
# one more before the last key arrives).
#
# usage: tests/boot.sh [BUILD_DIR]      (default: build)
#        UPDATE=1 tests/boot.sh         rewrite tests/expected/ from this run
#                                       (read `git diff` before committing)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUILD="${1:-build}"
TIMEOUT="${BOOT_TIMEOUT:-60}"
STEP_TIMEOUT="${STEP_TIMEOUT:-20}"
TMP="$(mktemp -d)"
trap 'exec 3>&- 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0
fail=0

# case NAME ARCH STATUS STEP...
case_() {
    local name=$1 arch=$2 want=$3
    shift 3
    local raw="$TMP/$name.raw" out="$TMP/$name.out" err="$TMP/$name.err"
    rm -f "$TMP/in"
    mkfifo "$TMP/in"
    : > "$raw"
    timeout "$TIMEOUT" "$ROOT/scripts/qemu.sh" "$arch" "$BUILD/timer-$arch.elf" < "$TMP/in" > "$raw" 2> "$err" &
    local pid=$!
    exec 3> "$TMP/in"
    local why=""
    local step
    for step in "$@"; do
        case "$step" in
            wait:*)
                local text=${step#wait:}
                local deadline=$((SECONDS + STEP_TIMEOUT))
                until grep -qF -- "$text" "$raw"; do
                    if [ "$SECONDS" -ge "$deadline" ] || ! kill -0 "$pid" 2>/dev/null; then
                        grep -qF -- "$text" "$raw" || why="never printed '$text'"
                        break
                    fi
                    sleep 0.1
                done
                ;;
            send:*)
                printf '%s' "${step#send:}" >&3
                ;;
        esac
        [ -n "$why" ] && break
    done
    exec 3>&-
    if [ -n "$why" ]; then
        kill "$pid" 2>/dev/null
    fi
    wait "$pid"
    local status=$?
    tr -d '\r' < "$raw" | sed -E -e 's/(rip|pc) 0x[0-9a-f]+/\1 0xN/' \
        -e 's/^quit after [0-9]+ ticks/quit after N ticks/' \
        -e '/^heartbeat ([4-9]|[1-9][0-9]+):/d' > "$out"
    if [ -n "$why" ]; then
        echo "FAIL $name: $why"
        sed 's/^/    /' "$out" "$err" | tail -20
        fail=$((fail + 1))
    elif [ "$status" -eq 124 ]; then
        echo "FAIL $name: QEMU did not exit within ${TIMEOUT}s"
        sed 's/^/    /' "$out" | tail -20
        fail=$((fail + 1))
    elif [ "$status" -ne "$want" ]; then
        echo "FAIL $name: exit status $status, expected $want"
        sed 's/^/    /' "$out" "$err" | tail -20
        fail=$((fail + 1))
    elif [ "${UPDATE:-0}" = 1 ]; then
        cp "$out" "$HERE/expected/$name.txt"
        echo "upd  $name (exit status $status)"
        pass=$((pass + 1))
    elif ! diff -u "$HERE/expected/$name.txt" "$out" > "$TMP/$name.diff"; then
        echo "FAIL $name: transcript differs from tests/expected/$name.txt"
        sed 's/^/    /' "$TMP/$name.diff"
        fail=$((fail + 1))
    else
        echo "ok   $name (exit status $status)"
        pass=$((pass + 1))
    fi
}

# Three heartbeats, a trap the kernel survives, an ignored key, quit.
TRAP_THEN_QUIT=("wait:heartbeat 3:" "send:t" "wait:trap 1:" "send:x" "wait:does nothing"
    "send:q" "wait:quit after")

# Each fault ends in the panic handler, with the fault's details.
case_ heartbeat-x86_64 x86_64 33 "${TRAP_THEN_QUIT[@]}"
case_ divide-error-x86_64 x86_64 37 "wait:heartbeat 1:" "send:d" "wait:PANIC"
case_ invalid-opcode-x86_64 x86_64 37 "wait:heartbeat 1:" "send:u" "wait:PANIC"
case_ protection-fault-x86_64 x86_64 37 "wait:heartbeat 1:" "send:g" "wait:PANIC"
case_ page-fault-x86_64 x86_64 37 "wait:heartbeat 1:" "send:p" "wait:PANIC"

case_ heartbeat-aarch64 aarch64 0 "${TRAP_THEN_QUIT[@]}"
case_ undefined-aarch64 aarch64 2 "wait:heartbeat 1:" "send:u" "wait:PANIC"
case_ data-abort-aarch64 aarch64 2 "wait:heartbeat 1:" "send:p" "wait:PANIC"
case_ alignment-aarch64 aarch64 2 "wait:heartbeat 1:" "send:a" "wait:PANIC"

echo "boot tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
