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

/* Check if a file is in ELF format.
 * Returns 1 if ELF, 0 otherwise. */
int elf_is_elf_file(const char *filename);

/* Load an ELF32 executable into emulator memory.
 * Returns entry point address on success, or 0 on error. */
uint32_t elf_load(m65832_cpu_t *cpu, const char *filename, int verbose);

#endif /* ELF_LOADER_H */
