# Design: bare-timer

## Overview

Two boards share one main loop. Each board's entry file brings the CPU up,
attaches its UART to the console and calls `timer.app.run(board)` with a
`Board` whose fields are the per-CPU operations as function values:
`setup` (install the handlers, start the timer and the UART's receive
interrupt), `enableInterrupts`, `idle`, `trap`, `fault(key)` and `exit`.
Interrupt handlers only record events in atomics; the main loop does the
printing.

```text
x86_64:  PIT --IRQ 0--> 8259 --0x20--> isrTimer --tick()---+
         COM1 --IRQ 4--> 8259 --0x24--> isrCom1 --pushKey()-+
         int3 --vector 3--> isrBreakpoint --recordTrap()----+--> run(): heartbeats, keys
aarch64: CNTV --INTID 27--> GIC --IRQ entry--> isrIrq ------+
         PL011 --INTID 33--> GIC --IRQ entry--> isrIrq -----+
         svc --sync entry--> isrSync (class 0x15) ----------+
faults --> handler: recordFault(...), unreachable --> @panic_handler --> report, exit 2
```

## Boards

| | x86_64 | aarch64 |
|---|---|---|
| Manifest | `package.lppkg` | `boards/aarch64/package.lppkg` |
| Entry points | IDT of 256 16-byte gates in a `buffer[uint64, 512]` placed by `@section(".idt")` on its own page; `lidt` | a naked `vectorTable` in `@section(".text.vectors")`, 2 KiB aligned; `msr vbar_el1` |
| Handler entry | `@interrupt(arch: "x86_64", has_error_code: ...)`, gate address from `lea` | `@interrupt(arch: "aarch64")`, reached by a branch in the vector table |
| Interrupt controller | 8259 pair, remapped to 0x20-0x2F; end of interrupt to port 0x20 | GICv2: acknowledge by reading `GICC_IAR`, end by writing `GICC_EOIR` |
| Timer | PIT channel 0, mode 2, divisor 11932 | EL1 virtual timer, `CNTV_TVAL_EL0 = CNTFRQ_EL0 / 100`, re-armed in the handler |
| UART input | 16550 IER bit 0 and MCR OUT2; IRQ 4 | PL011 `UARTIMSC.RXIM`; INTID 33 (SPI 1) |
| Trap | `int3` through a trap gate; the saved `rip` is the next instruction | `svc #0`; `ELR_EL1` is the next instruction |
| Faults | #DE, #UD, #DF, #GP, #PF handlers; `cr2` for #PF | one synchronous handler; class from `ESR_EL1`, address from `FAR_EL1` |
| Sleep | `hlt` | `wfi` |
| Exit | `isa-debug-exit` | semihosting `SYS_EXIT` |

The AArch64 frame type is named `ExceptionFrame`: in Loup 1.26.0
`InterruptFrame` is a built-in with the x86_64 fields, and importing a
struct of that name with other fields is an error. The AArch64 `@interrupt`
trampoline restores `ELR_EL1` from the (read-only) frame, so a handler cannot
step past a `brk`; `svc` is the trap that needs no adjustment.

## Modules

| Module | Contents |
|---|---|
| `source/main_x86_64.lpfree` | boot headers, `_start`, `setup`, the board, `@panic_handler` |
| `source/main_aarch64.lpfree` | `_start`, `setup`, the board, `@panic_handler` |
| `source/appinfo.lpfree` | name, version, statuses |
| `source/timer/board.lpfree` | `struct Board` |
| `source/timer/console.lpfree` | `attach(put)`, `putc`, `puts`, `putDec`, `putDec2`, `putHex` |
| `source/timer/state.lpfree` | tick count, key ring, trap and fault records; atomics only |
| `source/timer/app.lpfree` | `run(board)`: bring-up, the sleep loop, heartbeats, keys |
| `source/x86/port.lpfree`, `com1.lpfree`, `idt.lpfree`, `pic.lpfree`, `pit.lpfree`, `qemu.lpfree` | x86 devices |
| `source/x86/isr.lpfree` | the x86 handlers, the `@naked` spurious-IRQ stub, `installHandlers` |
| `source/x86/faults.lpfree` | `trap`, `provokeFault(key)`, `printFaultReport` |
| `source/arm/pl011.lpfree`, `gic.lpfree`, `timer.lpfree`, `qemu.lpfree` | aarch64 devices |
| `source/arm/isr.lpfree` | `ExceptionFrame`, `isrIrq`, `isrSync`, `vecUnexpected`, the vector table, `installVectors` |
| `source/arm/faults.lpfree` | `trap`, `provokeFault(key)`, `printFaultReport` |

## Interrupt rules this code keeps

- **Colour rule.** Handlers call only `@interruptSafe` functions (checked:
  `E_INTERRUPT_SAFE_VIOLATION`).
- **Shared data is atomic.** The tick count, the key ring's head and tail,
  and the trap and fault records are accessed only with `atomicLoadU64`,
  `atomicStoreU64` and `atomicFetchAddU64`. The key ring has one producer
  (the UART handler) and one consumer (the main loop), so it needs no lock.
- **Handlers do not print.** They record; the main loop reports. The panic
  handler prints with polled, buffer-free functions.
- **No `Result` in handlers.** Functions that return a `Result` keep it in a
  static block in 1.26.0 freestanding builds, which is not reentrant.
- **Spurious interrupts are not acknowledged:** the x86 IRQ 7 stub is a bare
  `iretq`; the GIC's INTID 1023 gets no end of interrupt.

## Differences from the roadmap

- The aarch64 version, a stretch goal, is included and tested.
- Keys, delivered by the UART's interrupt, drive the demonstration: they
  provoke a trap and the faults, so each handler is exercised in CI. The
  fault keys differ per CPU (AArch64 integer division does not trap, and it
  has no segment checks).
- `@section` is shown on the IDT and the vector table; `@naked` on the
  vector table, the spurious-IRQ stub and the entry stubs.

## Error handling

There are no recoverable errors at run time. A fault is recorded by its
handler, which then reaches `unreachable`; with `panic = "custom"` that
calls the board's `kernelPanic`, which masks interrupts, prints the panic
message and location and the fault record, and exits with status 2.

## Testing

`tests/boot.sh` runs QEMU with its serial input on a FIFO. Each case is a
list of `wait:TEXT` and `send:KEYS` steps; the transcript is compared with
`tests/expected/NAME.txt` after replacing instruction addresses
(`rip 0x...`, `pc 0x...`) and the tick count at quit time with `N`, and
dropping heartbeats after the third.

| Case | Steps | QEMU exit status |
|---|---|---|
| `heartbeat-x86_64`, `heartbeat-aarch64` | wait for heartbeat 3, `t`, `x`, `q` | 33, 0 |
| `divide-error-x86_64` | wait for heartbeat 1, `d` | 37 |
| `invalid-opcode-x86_64` | wait for heartbeat 1, `u` | 37 |
| `protection-fault-x86_64` | wait for heartbeat 1, `g` | 37 |
| `page-fault-x86_64` | wait for heartbeat 1, `p` | 37 |
| `undefined-aarch64` | wait for heartbeat 1, `u` | 2 |
| `data-abort-aarch64` | wait for heartbeat 1, `p` | 2 |
| `alignment-aarch64` | wait for heartbeat 1, `a` | 2 |

The timers run in real time under QEMU, so the suite takes about 15
seconds.
