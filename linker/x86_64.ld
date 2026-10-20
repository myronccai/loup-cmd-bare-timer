/* x86_64 image for `qemu-system-x86_64 -kernel`.
 *
 * Linked at 1 MiB. .boot holds the Multiboot2 header and the 32-bit entry;
 * .note.Xen carries the PVH entry note in its own PT_NOTE segment, which is
 * how QEMU finds where to enter the image. The interrupt descriptor table
 * (the .idt section) starts on a page of its own. The stack (64 KiB,
 * matching [freestanding] stack_size) is reserved after .bss and ends at
 * __stack_top.
 */
ENTRY(_start)

PHDRS {
    text PT_LOAD FLAGS(7);   /* RWX */
    note PT_NOTE FLAGS(4);   /* R   */
}

SECTIONS {
    . = 0x100000;
    __image_start = .;

    .boot : {
        KEEP(*(.multiboot))
        KEEP(*(.text.boot))
    } :text

    .note.Xen : { KEEP(*(.note.Xen)) } :text :note

    .text   : { *(.text .text.*) }       :text
    .rodata : { *(.rodata .rodata.*) }   :text
    .data   : { *(.data .data.*) }       :text
    .idt    : ALIGN(4096) { KEEP(*(.idt)) } :text
    .bss    : {
        *(.bss .bss.*)
        . = ALIGN(16);
        . = . + 65536;
        __stack_top = .;
    } :text

    __image_end = .;
}
