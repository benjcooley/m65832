ENTRY(_start)
SECTIONS {
    . = 0x1000;
    .text : { *(.text*) }
    . = 0x2000;
    .data : { *(.data*) *(.rodata*) }
    . = 0x3000;
    .bss : { *(.bss*) }
}
