/*
 * M65832 ELF Loader
 *
 * Shared ELF32 loading for both legacy and system modes.
 */

#include <stdio.h>
#include <string.h>
#include "elf_loader.h"

int elf_is_elf_file(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;
    
    uint32_t magic;
    size_t n = fread(&magic, 1, 4, f);
    fclose(f);
    
    return (n == 4 && magic == ELF_MAGIC);
}

uint32_t elf_load(m65832_cpu_t *cpu, const char *filename, int verbose) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s'\n", filename);
        return 0;
    }
    
    /* Read ELF header */
    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(ehdr), 1, f) != 1) {
        fprintf(stderr, "error: cannot read ELF header\n");
        fclose(f);
        return 0;
    }
    
    /* Validate ELF header */
    if (ehdr.e_magic != ELF_MAGIC) {
        fprintf(stderr, "error: not an ELF file\n");
        fclose(f);
        return 0;
    }
    
    if (ehdr.e_class != 1) {
        fprintf(stderr, "error: not a 32-bit ELF (class=%d)\n", ehdr.e_class);
        fclose(f);
        return 0;
    }
    
    if (ehdr.e_data != 1) {
        fprintf(stderr, "error: not little-endian ELF\n");
        fclose(f);
        return 0;
    }
    
    if (ehdr.e_type != ET_EXEC) {
        fprintf(stderr, "warning: ELF type is %d (expected executable)\n", ehdr.e_type);
    }
    
    if (verbose) {
        printf("ELF: entry=0x%08X, %d program headers\n", 
               ehdr.e_entry, ehdr.e_phnum);
    }
    
    /* Load program segments */
    uint32_t total_loaded = 0;
    for (int i = 0; i < ehdr.e_phnum; i++) {
        Elf32_Phdr phdr;
        
        fseek(f, ehdr.e_phoff + i * ehdr.e_phentsize, SEEK_SET);
        if (fread(&phdr, sizeof(phdr), 1, f) != 1) {
            fprintf(stderr, "error: cannot read program header %d\n", i);
            fclose(f);
            return 0;
        }
        
        if (phdr.p_type != PT_LOAD) continue;
        if (phdr.p_filesz == 0 && phdr.p_memsz == 0) continue;
        
        if (verbose) {
            printf("  LOAD: vaddr=0x%08X filesz=%u memsz=%u\n",
                   phdr.p_vaddr, phdr.p_filesz, phdr.p_memsz);
        }
        
        /* Check bounds */
        if (phdr.p_vaddr + phdr.p_memsz > cpu->memory_size) {
            fprintf(stderr, "error: segment exceeds memory (0x%X + %u > %zu)\n",
                    phdr.p_vaddr, phdr.p_memsz, cpu->memory_size);
            fclose(f);
            return 0;
        }
        
        /* Zero the memory region first (for .bss) */
        for (uint32_t j = 0; j < phdr.p_memsz; j++) {
            m65832_emu_write8(cpu, phdr.p_vaddr + j, 0);
        }
        
        /* Load file contents */
        if (phdr.p_filesz > 0) {
            fseek(f, phdr.p_offset, SEEK_SET);
            for (uint32_t j = 0; j < phdr.p_filesz; j++) {
                int c = fgetc(f);
                if (c == EOF) {
                    fprintf(stderr, "error: unexpected end of file\n");
                    fclose(f);
                    return 0;
                }
                m65832_emu_write8(cpu, phdr.p_vaddr + j, (uint8_t)c);
            }
            total_loaded += phdr.p_filesz;
        }
    }
    
    if (verbose) {
        printf("Loaded %u bytes from ELF\n", total_loaded);
    }
    
    fclose(f);
    return ehdr.e_entry;
}
