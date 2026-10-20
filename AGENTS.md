# AGENTS.md

This repository is `loup-cmd-bare-timer`, a kernel driven by interrupts, in
the loup-cmd series of Loup example applications. It is `freestanding` Loup
(`.lpfree`): no operating system, no heap, no exceptions. It is built for
two boards (x86-64 on QEMU `pc`, AArch64 on QEMU `virt`) and tested by
booting it under QEMU, waiting for its output and typing keys.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` and
`skills/loup-programmer/references/freestanding.md` before writing or
changing any Loup code in this repository. Load the other references only as
needed.

## Code layout

```text
.
├── package.lppkg                # x86_64 board: [build] entry/mode/arch/panic, [linker], [freestanding]
├── boards/aarch64/package.lppkg # aarch64 board: the same keys; paths relative to its directory
├── linker/
│   ├── x86_64.ld                # 1 MiB; .multiboot/.text.boot first; .note.Xen; .idt page-aligned
│   └── aarch64.ld               # 0x40080000; .text.boot first; .text.vectors 2 KiB aligned
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main_x86_64.lpfree       # boot headers, _start, setup (IDT, 8259, PIT), Board, @panic_handler
│   ├── main_aarch64.lpfree      # _start, setup (vectors, GIC, timer), Board, @panic_handler
│   ├── appinfo.lpfree           # APP_NAME, APP_VERSION, STATUS_*
│   ├── timer/                   # shared by both boards
│   │   ├── board.lpfree         # struct Board: names and per-CPU operations as function values
│   │   ├── console.lpfree       # attach(put), putc, puts, putDec, putDec2, putHex
│   │   ├── state.lpfree         # ticks, key ring, trap and fault records (atomics only)
│   │   └── app.lpfree           # run(board): the hlt/wfi loop, heartbeats, keys
│   ├── x86/                     # port, com1, idt, pic, pit, isr (handlers), faults, qemu
│   └── arm/                     # pl011, gic, timer, isr (vectors, handlers), faults, qemu
├── scripts/qemu.sh              # the QEMU command line for each board
├── tests/
│   ├── boot.sh                  # boot tests: wait:/send: steps, transcripts and exit statuses
│   └── expected/                # expected transcripts (addresses and quit-time ticks as N)
├── specs/bare-timer/            # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs lld, QEMU and Loup, runs `make ci`, uploads the images
└── build/                       # build output (git-ignored)
```

## Build, run and test

Prerequisites: Linux x86-64, Loup 1.26.0 (`loup` and `loup-bootstrap` on
`PATH`), `make`, `clang`, `ld.lld`, `qemu-system-x86_64` and
`qemu-system-aarch64`.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Type-check | `make check` | both boards; one expected frame warning per interrupt handler |
| Build | `make build` | `build/timer-x86_64.elf`, `build/timer-aarch64.elf` |
| Build one board | `make build/timer-aarch64.elf` | |
| Boot tests | `make boot` | `tests/boot.sh`: nine cases, about 15 seconds (the timers run in real time) |
| Refresh expected transcripts | `UPDATE=1 bash tests/boot.sh` | then read `git diff tests/expected` before committing |
| Use the kernel | `make run` / `make run ARCH=aarch64` | keys go to the kernel; `q` quits |
| Everything CI runs | `make ci` | check, build, boot |
| Clean | `make clean` | removes `build/` and `.temp/` |

Run `make ci` before reporting a change as done. `loup-bootstrap check`
accepts things the freestanding back ends reject or miscompile, so only a
boot proves a change. Do not call `loup check` on Linux x86-64 (the
self-hosted driver refuses it).

## Making a change

1. Update the spec in `specs/bare-timer/`.
2. Change the code under `source/` (or `linker/`).
3. Add or change a case at the end of `tests/boot.sh`.
4. Run `make build`, then `UPDATE=1 bash tests/boot.sh`, read the diff of
   `tests/expected/`, then `make ci`.
5. Tick the finished tasks in `specs/bare-timer/tasks.md`.

## Conventions

- Every source file is `@mode(freestanding)` with the `.lpfree` extension.
  Each board's entry file has the single `@entry` (`_start`).
- Code that differs per CPU lives in `source/x86/`, `source/arm/` and the two
  `main_*.lpfree` files; `source/timer/` must build for both boards.
- Interrupt handlers call only `@interruptSafe` functions, never print, and
  share data with the main loop only through the atomic intrinsics. Do not
  call a function that returns a `Result` from interrupt context (1.26.0
  keeps the result in a static block).
- Aggregate locals (buffers, structs) in `@interruptSafe` code must be
  `onstack`.
- On x86, a new handler needs a gate in `installHandlers` and an address
  function using `lea` (addressOf takes variables only). On AArch64, a new
  exception entry is a branch in `vectorTable`.
- The AArch64 frame struct is `ExceptionFrame`: in 1.26.0 `InterruptFrame`
  is a built-in with the x86_64 fields, and an imported struct of that name
  with other fields is an error.
- The llbe back end (the AArch64 default) does not assemble `svc`, `udf`,
  `brk` or `hlt #imm`; write them as `.inst` encodings.
- Faults record what happened and reach `unreachable`; the panic handler
  prints the record with the polled, buffer-free console functions.
- Do not name a local that holds a function value like a builtin (`exit`,
  `read`): the call links to the C symbol.
- Sized integers (`uint8` ... `uint32`) do not wrap in 1.26.0 freestanding
  builds; compute in `uint64` and mask when wrap-around matters.
- Keep `APP_VERSION` in `source/appinfo.lpfree` equal to `version` in both
  manifests.
- The skill documents toolchain 1.25.1; this repository targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
