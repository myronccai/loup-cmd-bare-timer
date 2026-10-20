# Requirements: bare-timer

## Introduction

`bare-timer` is a kernel that runs on interrupts. It sets up the CPU's
interrupt entry points and interrupt controller, programs a timer at
100 Hz and sleeps until interrupts wake it: the timer handler keeps the
uptime, the serial port's handler queues keys, and the main loop prints a
heartbeat every second and acts on the keys. Keys also provoke a trap the
kernel survives and CPU faults whose handlers report through the panic
path. It runs on x86-64 (QEMU `pc`: IDT, 8259, PIT) and AArch64 (QEMU
`virt`: vector table, GICv2, generic timer). It is the interrupt example of
the loup-cmd series.

## Requirements

### Requirement 1: Start-up

**User Story:** As a reader, I want the kernel to say what it set up so that
I can follow the bring-up sequence on the console.

#### Acceptance Criteria

1. WHEN the image boots, THE kernel SHALL print
   `loup-cmd-bare-timer 0.1.0 on ARCH`.
2. ON x86_64, THE kernel SHALL install IDT gates for vectors 0 (#DE), 3
   (#BP, a trap gate), 6 (#UD), 8 (#DF), 13 (#GP), 14 (#PF), 0x20 (IRQ 0),
   0x24 (IRQ 4) and 0x27 (spurious IRQ 7), load the table with `lidt`, remap
   the 8259 pair to vectors 0x20-0x2F with only IRQ 0 and IRQ 4 unmasked,
   program PIT channel 0 in mode 2 with divisor 11932 (100 Hz) and enable
   the 16550's receive interrupt, printing one line per step.
3. ON aarch64, THE kernel SHALL install a 2 KiB-aligned vector table in
   `VBAR_EL1`, enable the GICv2 with INTID 27 (EL1 virtual timer) and 33
   (PL011) routed to CPU 0, start the virtual timer at `CNTFRQ_EL0 / 100`
   counts and enable the PL011's receive interrupt, printing one line per
   step.
4. THE kernel SHALL list the keys, unmask interrupts and print
   `interrupts on`.

### Requirement 2: Timer and heartbeat

**User Story:** As a user, I want a heartbeat with the uptime so that I can
see the timer interrupt working.

#### Acceptance Criteria

1. WHEN the timer interrupt arrives, THE handler SHALL add one to the tick
   count (atomically) and acknowledge the interrupt (8259 end of interrupt;
   on aarch64, re-arm the timer and write the GIC's end-of-interrupt
   register).
2. THE main loop SHALL sleep between interrupts (`hlt`, `wfi`).
3. WHEN the tick count reaches each multiple of 100, THE main loop SHALL
   print `heartbeat N: uptime HH:MM:SS (T ticks)`, where T is that multiple
   and N counts heartbeats from 1.

### Requirement 3: Keys

**User Story:** As a user at the serial console, I want keys to drive the
kernel so that I can try each handler.

#### Acceptance Criteria

1. WHEN a byte arrives at the UART, THE UART handler SHALL read every
   waiting byte into a 16-entry ring shared with the main loop through
   atomics.
2. WHEN `t` is read, THE kernel SHALL execute the trap instruction (`int3`
   on x86_64, `svc #0` on aarch64); THE handler SHALL record the return
   address and return, and the main loop SHALL print
   `trap N: NAME handled, resumed at PC 0x...` and keep running.
3. WHEN `q` is read, THE kernel SHALL print
   `quit after T ticks and N trap(s)` and exit with status 0.
4. ON x86_64, WHEN `d`, `u`, `g` or `p` is read, THE kernel SHALL say what
   it is about to do and cause a divide error, an invalid opcode, a general
   protection fault (a non-canonical address) or a page fault (a read at
   `0x80000000`, outside the identity map).
5. ON aarch64, WHEN `u`, `p` or `a` is read, THE kernel SHALL say what it is
   about to do and cause an undefined instruction (`udf #0`), a data abort
   (a read at `0x09fff000`, a hole in the device map) or an alignment fault
   (a word read at `0x44000001` after turning on alignment checking with
   `SCTLR_EL1.A`).
6. WHEN Enter is read, THE kernel SHALL ignore it; WHEN any other key is
   read, THE kernel SHALL print `key 'K' does nothing;` and the key list.

### Requirement 4: Faults through the panic path

**User Story:** As a developer, I want a fault reported with its details so
that a crash is diagnosable instead of a silent reset.

#### Acceptance Criteria

1. THE manifests SHALL set `panic = "custom"`; each board SHALL declare a
   `@panic_handler`.
2. WHEN a fault is raised, THE handler SHALL record its kind (x86 vector or
   aarch64 exception class), error code or syndrome, faulting instruction
   and, where the CPU gives one, the faulting address (`cr2`, `FAR_EL1`),
   then reach `unreachable`.
3. WHEN a panic happens, THE panic handler SHALL mask interrupts, print
   `PANIC: MESSAGE at FILE:LINE`, then, after a fault, one line
   `  fault: NAME (...), ...` with the recorded details, and exit with
   status 2.
4. THE handlers SHALL call only `@interruptSafe` functions, and SHALL share
   data with the main loop only through atomic intrinsics.

### Requirement 5: Exit status

**User Story:** As a CI pipeline, I want QEMU's exit status to say how the
run ended.

#### Acceptance Criteria

1. ON x86_64, THE kernel SHALL end a run by writing `0x10 | status` to
   `isa-debug-exit` at port `0xF4` (QEMU exits with 33 after `q`, 37 after a
   panic); ON aarch64, by semihosting `SYS_EXIT` with the status (0 or 2).

### Requirement 6: Build and test

**User Story:** As a maintainer, I want one command that checks, builds and
boot-tests both kernels.

#### Acceptance Criteria

1. `make check` SHALL type-check both boards with `loup-bootstrap check`.
2. `make build` SHALL build `build/timer-x86_64.elf` and
   `build/timer-aarch64.elf` with `loup build --target freestanding`.
3. `make boot` SHALL boot each kernel under QEMU for each test case, wait
   for given output, type keys, and compare the transcript and QEMU's exit
   status with `tests/expected/`: per board, three heartbeats, a trap, an
   ignored key and `q`, and one case per fault key.
4. `make ci` SHALL run `check`, `build` and `boot`.
