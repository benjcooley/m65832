/* m65832_sys.ld - Linker script for emulator system-mode tests */
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00100000, LENGTH = 512K
    RAM (rwx) : ORIGIN = 0x00180000, LENGTH = 512K
    DP  (rw)  : ORIGIN = 0x00004000, LENGTH = 256
}

_stack_top = 0x001FFFFC;

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        KEEP(*(.text.startup))
        KEEP(*(.text.startup.*))
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
    } > ROM

    .init_array :
    {
        . = ALIGN(4);
        __preinit_array_start = .;
        KEEP(*(.preinit_array*))
        __preinit_array_end = .;
        __init_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        KEEP(*(.init_array))
        __init_array_end = .;
    } > ROM

    .fini_array :
    {
        . = ALIGN(4);
        __fini_array_start = .;
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        KEEP(*(.fini_array))
        __fini_array_end = .;
    } > ROM

    .tdata :
    {
        . = ALIGN(4);
        __tdata_start = .;
        *(.tdata .tdata.*)
        __tdata_end = .;
    } > RAM AT > ROM

    __tdata_source = LOADADDR(.tdata);
    __tdata_size = __tdata_end - __tdata_start;

    .tbss (NOLOAD) :
    {
        . = ALIGN(4);
        __tbss_start = .;
        *(.tbss .tbss.*)
        __tbss_end = .;
    } > RAM

    __tbss_size = __tbss_end - __tbss_start;
    __tls_size = __tbss_end - __tdata_start;
    __tls_align = MAX(ALIGNOF(.tdata), ALIGNOF(.tbss));

    .data :
    {
        . = ALIGN(4);
        _data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > RAM AT > ROM

    _data_load = LOADADDR(.data);

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM

    .heap (NOLOAD) :
    {
        . = ALIGN(4);
        _end = .;
        end = .;
        _heap_start = .;
        . = ORIGIN(RAM) + LENGTH(RAM) - 64K;
        _heap_end = .;
    } > RAM

    .dp (NOLOAD) :
    {
        *(.dp)
        *(.dp.*)
    } > DP

    /DISCARD/ :
    {
        *(.comment)
        *(.note.*)
        *(.eh_frame*)
        *(.ARM.*)
    }
}

PROVIDE(_end = _bss_end);
PROVIDE(end = _bss_end);
PROVIDE(__heap_start = _heap_start);
PROVIDE(__heap_end = _heap_end);
