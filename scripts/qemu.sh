#!/usr/bin/env bash
# Boot a timer kernel under QEMU, with the guest's serial port on this
# script's standard input and output. Keys (Ctrl-C too) go to the kernel;
# press q to quit. QEMU exits when the kernel reports its status
# (isa-debug-exit on x86_64, semihosting on aarch64).
#
# usage: scripts/qemu.sh ARCH IMAGE [QEMU-ARGS...]
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: scripts/qemu.sh ARCH IMAGE [QEMU-ARGS...]" >&2
    exit 2
fi
arch=$1
image=$2
shift 2

serial=(-chardev stdio,id=console,signal=off -serial chardev:console)

case "$arch" in
    x86_64)
        exec qemu-system-x86_64 -m 128M -display none -monitor none -nic none \
            -no-reboot "${serial[@]}" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
            -kernel "$image" "$@"
        ;;
    aarch64)
        exec qemu-system-aarch64 -M virt -cpu cortex-a53 -m 256M \
            -display none -monitor none -nic none -no-reboot "${serial[@]}" \
            -semihosting \
            -kernel "$image" "$@"
        ;;
    *)
        echo "qemu.sh: unknown arch '$arch' (x86_64 or aarch64)" >&2
        exit 2
        ;;
esac
