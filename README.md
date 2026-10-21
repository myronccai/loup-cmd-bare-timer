# loup-cmd-bare-timer

Interrupts on bare metal, in [Loup](https://code-craft.ai/references/loup):
a kernel that sets up its interrupt controller and a 100 Hz timer, prints a
heartbeat with its uptime, and takes keys from the serial port's interrupt
to trigger a trap it survives and CPU faults that it reports through the
panic handler. On x86-64: an IDT, the 8259 pair remapped, the PIT. On
AArch64: a vector table, the GICv2, the generic timer.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is `freestanding` Loup (`.lpfree`), booted under QEMU.

## What this example shows

| Feature | Where |
|---|---|
| `@interrupt(arch: "x86_64", has_error_code: ...)` handlers with a `borrow InterruptFrame`, and the error code for #DF, #GP, #PF | [`source/x86/isr.lpfree`](source/x86/isr.lpfree) |
| `@interrupt(arch: "aarch64")` handlers for the IRQ and synchronous entries, reading the exception syndrome | [`source/arm/isr.lpfree`](source/arm/isr.lpfree) |
| `@interruptSafe` call chains: everything a handler calls is checked | `tick`, `pushKey`, `picEoi`, `gicAcknowledge`, `timerRearm`, ... |
| `@naked` code: the AArch64 vector table, the x86 spurious-IRQ stub (`iretq` only), the entry stubs | `vectorTable`, `isrSpurious`, `_start` |
| `@section`: the IDT on a page of its own, the 2 KiB-aligned vector table, the boot headers | `idt` in [`source/x86/idt.lpfree`](source/x86/idt.lpfree), [`linker/`](linker) |
| IDT gates in a `buffer[uint64, 512]`, handler addresses with `lea`, `lidt`; interrupt vs trap gates | [`source/x86/idt.lpfree`](source/x86/idt.lpfree) |
| The 8259 remap and masks, the 8254 PIT at 100 Hz, a 16550 receive interrupt | [`source/x86/`](source/x86) |
| The GICv2 (distributor, CPU interface, acknowledge, end of interrupt), the EL1 virtual timer, a PL011 receive interrupt | [`source/arm/`](source/arm) |
| Data shared with handlers through atomics only: the tick count, a lock-free key ring | [`source/timer/state.lpfree`](source/timer/state.lpfree) |
| Fault handlers that record the fault and report through the panic path (`unreachable` + `panic = "custom"`) | `isrPageFault`, `isrSync`, `kernelPanic` |
| One main loop for both CPUs: the board passes its operations as function values | [`source/timer/app.lpfree`](source/timer/app.lpfree), [`source/timer/board.lpfree`](source/timer/board.lpfree) |
| Testing an interrupt-driven kernel: wait for output, type keys, compare | [`tests/boot.sh`](tests/boot.sh) |

The boot code (Multiboot2 header, PVH note, long-mode trampoline on x86-64)
is the same as in [loup-cmd-bare-hello](https://github.com/myronccai/loup-cmd-bare-hello),
which explains it.

## Requirements

- Linux x86-64 (freestanding images are built on Linux only).
- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, `clang`, `ld.lld` and QEMU for both architectures. On Ubuntu:

  ```sh
  sudo apt-get install clang lld qemu-system-x86 qemu-system-arm
  ```

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Build and run

```sh
make check               # type-check both boards (loup-bootstrap check)
make build               # build/timer-x86_64.elf and build/timer-aarch64.elf
make boot                # boot both under QEMU, press keys, compare with tests/expected/
make ci                  # check, build, boot
make run                 # the x86_64 kernel on this terminal; press q to quit
make run ARCH=aarch64    # the same for aarch64
```

`make build` runs `loup build --target freestanding --arch x86_64 -o
build/timer-x86_64.elf .` and the same with `--arch aarch64 ...
boards/aarch64`; [`scripts/qemu.sh`](scripts/qemu.sh) has the QEMU command
lines. The serial port is connected with `-chardev stdio,signal=off`, so
every key, Ctrl-C included, goes to the kernel.

`make check` prints one `E_INTERRUPT_SAFE_VIOLATION` warning per
interrupt handler, "marshals a struct by value": the frame parameter is a
`borrow`, as the language prescribes, and Loup 1.26.0 reports it anyway. It
is expected and does not fail the check.

## Usage

On x86-64: three heartbeats, `t` for a trap, then `q`:

```text
$ scripts/qemu.sh x86_64 build/timer-x86_64.elf; echo "QEMU exit status $?"
loup-cmd-bare-timer 0.1.0 on x86_64
idt: 9 gates installed, loaded with lidt
pic: 8259 pair remapped to vectors 0x20-0x2f; IRQ 0 (PIT) and IRQ 4 (COM1) unmasked
pit: channel 0 at 100 Hz (divisor 11932)
keys: t trap, d divide error, u invalid opcode, g protection fault, p page fault, q quit
interrupts on
heartbeat 1: uptime 00:00:01 (100 ticks)
heartbeat 2: uptime 00:00:02 (200 ticks)
heartbeat 3: uptime 00:00:03 (300 ticks)
trap 1: int3 -> #BP (vector 3) handled, resumed at rip 0x103a85
quit after 360 ticks and 1 trap(s)
QEMU exit status 33
```

`p` reads memory outside the identity map; the page-fault handler records
the fault and panics (QEMU exits with 37):

```text
heartbeat 1: uptime 00:00:01 (100 ticks)
reading unmapped memory at 0x80000000
PANIC: reached an `unreachable` expression at x86/isr.lpfree:110
  fault: #PF page fault (vector 14), error 0x0, rip 0x103b6c, address 0x80000000
```

On AArch64, two heartbeats, `t`, `q`:

```text
$ scripts/qemu.sh aarch64 build/timer-aarch64.elf; echo "QEMU exit status $?"
loup-cmd-bare-timer 0.1.0 on aarch64
vectors: VBAR_EL1 = 0x40080800 (16 entries, 2 KiB aligned)
gic: GICv2 on; INTID 27 (virtual timer) and 33 (PL011) enabled
timer: CNTV at 100 Hz (625000 counts of 62500000 Hz)
keys: t trap, u undefined instruction, p data abort, a alignment fault, q quit
interrupts on
heartbeat 1: uptime 00:00:01 (100 ticks)
heartbeat 2: uptime 00:00:02 (200 ticks)
trap 1: svc -> SVC (class 0x15) handled, resumed at pc 0x40082cc8
quit after 264 ticks and 1 trap(s)
QEMU exit status 0
```

and `a`, a word read at an odd address with alignment checking on (QEMU
exits with 2):

```text
heartbeat 1: uptime 00:00:01 (100 ticks)
alignment checks on; reading a word at 0x44000001
PANIC: reached an `unreachable` expression at arm/isr.lpfree:81
  fault: data abort (class 0x25), esr 0x96000021, pc 0x40082f08, address 0x44000001
```

### Keys

| Key | x86-64 | AArch64 | Ends the run |
|---|---|---|---|
| `t` | `int3`: #BP, vector 3 (a trap gate); the handler records `rip` and returns | `svc #0`: synchronous exception class 0x15; the handler records `pc` and returns | no |
| `d` | `div` by zero: #DE, vector 0 | (integer division does not trap on AArch64) | panic |
| `u` | `ud2`: #UD, vector 6 | `udf #0`: class 0x00 | panic |
| `g` | load from a non-canonical address: #GP, vector 13 | | panic |
| `p` | read at `0x80000000`, outside the identity map: #PF, vector 14, address from `cr2` | read at `0x09fff000`, a hole in the device map: data abort, class 0x25, address from `FAR_EL1` | panic |
| `a` | | sets `SCTLR_EL1.A` (alignment checking), then reads a word at `0x44000001`: data abort (alignment), class 0x25 | panic |
| `q` | quit | quit | status 0 |

On x86-64 a double fault (#DF, vector 8) has a handler too; no key provokes
one. On AArch64 every vector other than the synchronous and IRQ entries
reports through the panic path.

### Exit statuses

| Event | Status | QEMU exit status, x86-64 | QEMU exit status, AArch64 |
|---|---|---|---|
| `q` | 0 | 33 | 0 |
| panic (a fault) | 2 | 37 | 2 |

x86-64 writes `0x10 | status` to `isa-debug-exit`, which makes QEMU exit
with `(value << 1) | 1`; AArch64 passes the status to semihosting
`SYS_EXIT`.

## Differences from the roadmap

- The resumable trap is `int3` on x86-64 and `svc` on AArch64. A `brk`
  cannot be resumed with Loup 1.26.0: the `@interrupt` trampoline restores
  `ELR_EL1` from the read-only frame, so a handler cannot step past the
  instruction, whereas `svc` returns to the next one by itself.
- The faults are provoked from the keyboard, through a second interrupt
  source (the UART's), so that CI exercises every handler. The fault keys
  differ per CPU.
- Shared data uses atomic intrinsics rather than `InterruptGuard`: one
  writer and one reader per variable need no masking.
- The aarch64 version, a stretch goal, is included and tested.

## Layout

```text
package.lppkg                 # x86_64 board: freestanding, panic = "custom", [linker], [freestanding]
boards/aarch64/package.lppkg  # aarch64 board: the same keys
linker/x86_64.ld              # 1 MiB; boot headers first; .idt on its own page; 64 KiB stack
linker/aarch64.ld             # 0x40080000; vector table 2 KiB aligned; 64 KiB stack
source/main_x86_64.lpfree     # x86 boot headers, _start, setup, @panic_handler
source/main_aarch64.lpfree    # aarch64 _start, setup, @panic_handler
source/x86/                   # port I/O, COM1, IDT, 8259, PIT, handlers, faults, QEMU exit
source/arm/                   # PL011, GICv2, generic timer, vectors and handlers, faults, QEMU exit
source/timer/                 # shared: Board, console, atomic state, the main loop
scripts/qemu.sh               # the QEMU command line for each board
tests/boot.sh                 # boot tests (make boot)
tests/expected/               # expected transcripts
specs/bare-timer/             # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
