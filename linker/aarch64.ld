/* AArch64 image for `qemu-system-aarch64 -M virt -kernel`.
 *
 * QEMU's virt machine has RAM at 0x40000000 and keeps its device tree at the
 * start of it, so the image is linked at 0x40080000. _start (.text.boot)
 * comes first. The exception vector table must be 2 KiB aligned (VBAR_EL1
 * bits 10:0 are RES0), so .text.vectors gets an aligned section of its own. The stack (64 KiB, matching [freestanding] stack_size) is
 * reserved after .bss and ends at __stack_top.
 */
ENTRY(_start)

PHDRS {
    text PT_LOAD FLAGS(7);   /* RWX */
}

SECTIONS {
    . = 0x40080000;
    __image_start = .;

    .text.boot : { KEEP(*(.text.boot)) }   :text
    . = ALIGN(2048);
    .vectors   : { KEEP(*(.text.vectors)) } :text
    .text      : { *(.text .text.*) }       :text
    .rodata    : { *(.rodata .rodata.*) }   :text
    .data      : { *(.data .data.*) }       :text
    .bss       : {
        *(.bss .bss.*)
        . = ALIGN(16);
        . = . + 65536;
        __stack_top = .;
    } :text

    __image_end = .;
}
