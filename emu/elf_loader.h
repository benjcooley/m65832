/*
 * M65832 ELF Loader
 *
 * Shared ELF32 loading for both legacy and system modes.
 */

#ifndef ELF_LOADER_H
#define ELF_LOADER_H

#include <stdint.h>
#include "m65832emu.h"

/* =========================================================================
 * ELF32 Definitions (bare minimum for loading)
 * ========================================================================= */

#define ELF_MAGIC       0x464C457F  /* "\x7FELF" */
#define ET_EXEC         2           /* Executable */
#define EM_M65832       0x6583      /* M65832 machine type (custom) */
#define PT_LOAD         1           /* Loadable segment */
#define PT_NULL         0           /* Unused */
#define SHT_SYMTAB      2           /* Symbol table */
#define SHT_STRTAB      3           /* String table */
#define SHT_PROGBITS    1           /* Program data (includes .debug_line) */
#define STT_NOTYPE      0
#define STT_OBJECT      1
#define STT_FUNC        2
#define ELF32_ST_TYPE(i) ((i) & 0xf)

typedef struct {
    uint32_t e_magic;       /* ELF magic */
    uint8_t  e_class;       /* 1=32-bit, 2=64-bit */
    uint8_t  e_data;        /* 1=LE, 2=BE */
    uint8_t  e_version;     /* 1 */
    uint8_t  e_osabi;       /* OS/ABI */
    uint8_t  e_pad[8];      /* Padding */
    uint16_t e_type;        /* Object type */
    uint16_t e_machine;     /* Machine type */
    uint32_t e_version2;    /* Version */
    uint32_t e_entry;       /* Entry point */
    uint32_t e_phoff;       /* Program header offset */
    uint32_t e_shoff;       /* Section header offset */
    uint32_t e_flags;       /* Flags */
    uint16_t e_ehsize;      /* ELF header size */
    uint16_t e_phentsize;   /* Program header entry size */
    uint16_t e_phnum;       /* Number of program headers */
    uint16_t e_shentsize;   /* Section header entry size */
    uint16_t e_shnum;       /* Number of section headers */
    uint16_t e_shstrndx;    /* Section name string table index */
} Elf32_Ehdr;

typedef struct {
    uint32_t p_type;        /* Segment type */
    uint32_t p_offset;      /* File offset */
    uint32_t p_vaddr;       /* Virtual address */
    uint32_t p_paddr;       /* Physical address */
    uint32_t p_filesz;      /* Size in file */
    uint32_t p_memsz;       /* Size in memory */
    uint32_t p_flags;       /* Flags */
    uint32_t p_align;       /* Alignment */
} Elf32_Phdr;

typedef struct {
    uint32_t sh_name;
    uint32_t sh_type;
    uint32_t sh_flags;
    uint32_t sh_addr;
    uint32_t sh_offset;
    uint32_t sh_size;
    uint32_t sh_link;       /* For SYMTAB: index of associated STRTAB */
    uint32_t sh_info;
    uint32_t sh_addralign;
    uint32_t sh_entsize;
} Elf32_Shdr;

typedef struct {
    uint32_t st_name;       /* Index into string table */
    uint32_t st_value;      /* Symbol address */
    uint32_t st_size;       /* Symbol size in bytes */
    uint8_t  st_info;       /* Type and binding */
    uint8_t  st_other;
    uint16_t st_shndx;
} Elf32_Sym;

/* =========================================================================
 * Symbol Table
 * ========================================================================= */

typedef struct {
    uint32_t    addr;
    uint32_t    size;
    const char *name;       /* Points into strtab */
} elf_symbol_t;

typedef struct {
    elf_symbol_t *entries;  /* Sorted by addr */
    int           count;
    char         *strtab;   /* Backing string table */
} elf_symtab_t;

/* Load symbol table from an ELF file (does not load code). */
elf_symtab_t *elf_load_symbols(const char *filename, int verbose);

/* Look up the symbol containing addr. Returns name or NULL.
 * If offset_out is non-NULL, stores the offset within the symbol. */
const char *elf_lookup_symbol(elf_symtab_t *tab, uint32_t addr,
                              uint32_t *offset_out);

/* Find a symbol by name. Returns address or 0 if not found. */
uint32_t elf_find_symbol(elf_symtab_t *tab, const char *name);

/* Free symbol table. */
void elf_free_symbols(elf_symtab_t *tab);

/* =========================================================================
 * DWARF Line Number Table (.debug_line)
 * ========================================================================= */

typedef struct {
    uint32_t addr;
    uint16_t file_idx;      /* Index into linetab->files[] */
    uint32_t line;
} elf_line_entry_t;

typedef struct {
    elf_line_entry_t *entries;  /* Sorted by addr */
    int               count;
    char            **files;    /* File path strings (dir/name) */
    int               num_files;
} elf_linetab_t;

/* Load DWARF .debug_line from an ELF file.
 * Returns NULL if no debug info or parse error. */
elf_linetab_t *elf_load_lines(const char *filename, int verbose);

/* Look up source file:line for an address.
 * Returns file path or NULL. If line_out is non-NULL, stores line number. */
const char *elf_lookup_line(elf_linetab_t *tab, uint32_t addr, int *line_out);

/* Free line table. */
void elf_free_lines(elf_linetab_t *tab);

/* Get the VA→PA offset from the first LOAD segment.
 * Returns vaddr - paddr (e.g. 0x7FF00000 for PAGE_OFFSET=0x80000000,
 * PHYS_OFFSET=0x00100000).  Returns 0 if not an ELF or no LOAD segments. */
uint32_t elf_get_va_offset(const char *filename);

/* Check if a file is in ELF format.
 * Returns 1 if ELF, 0 otherwise. */
int elf_is_elf_file(const char *filename);

/* Load an ELF32 executable into emulator memory.
 * Returns entry point address on success, or 0 on error. */
uint32_t elf_load(m65832_cpu_t *cpu, const char *filename, int verbose);

#endif /* ELF_LOADER_H */
