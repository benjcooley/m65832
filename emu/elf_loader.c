/*
 * M65832 ELF Loader
 *
 * Shared ELF32 loading for both legacy and system modes.
 */

#include <stdio.h>
#include <stdlib.h>
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

uint32_t elf_get_va_offset(const char *filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) return 0;

    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(ehdr), 1, f) != 1 || ehdr.e_magic != ELF_MAGIC) {
        fclose(f);
        return 0;
    }

    for (int i = 0; i < ehdr.e_phnum; i++) {
        Elf32_Phdr phdr;
        fseek(f, ehdr.e_phoff + i * ehdr.e_phentsize, SEEK_SET);
        if (fread(&phdr, sizeof(phdr), 1, f) != 1) break;
        if (phdr.p_type == PT_LOAD && phdr.p_filesz > 0) {
            fclose(f);
            return phdr.p_vaddr - phdr.p_paddr;
        }
    }

    fclose(f);
    return 0;
}

/* =========================================================================
 * Symbol Table Loading
 * ========================================================================= */

static int symbol_cmp(const void *a, const void *b) {
    const elf_symbol_t *sa = (const elf_symbol_t *)a;
    const elf_symbol_t *sb = (const elf_symbol_t *)b;
    if (sa->addr < sb->addr) return -1;
    if (sa->addr > sb->addr) return 1;
    return 0;
}

elf_symtab_t *elf_load_symbols(const char *filename, int verbose) {
    FILE *f = fopen(filename, "rb");
    if (!f) return NULL;

    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(ehdr), 1, f) != 1 || ehdr.e_magic != ELF_MAGIC) {
        fclose(f);
        return NULL;
    }
    if (ehdr.e_shoff == 0 || ehdr.e_shnum == 0) {
        fclose(f);
        return NULL;
    }

    /* Read all section headers */
    Elf32_Shdr *shdrs = calloc(ehdr.e_shnum, sizeof(Elf32_Shdr));
    if (!shdrs) { fclose(f); return NULL; }

    fseek(f, ehdr.e_shoff, SEEK_SET);
    if (fread(shdrs, sizeof(Elf32_Shdr), ehdr.e_shnum, f) != ehdr.e_shnum) {
        free(shdrs);
        fclose(f);
        return NULL;
    }

    /* Find SHT_SYMTAB section */
    int symtab_idx = -1;
    for (int i = 0; i < ehdr.e_shnum; i++) {
        if (shdrs[i].sh_type == SHT_SYMTAB) {
            symtab_idx = i;
            break;
        }
    }
    if (symtab_idx < 0) {
        free(shdrs);
        fclose(f);
        return NULL;
    }

    Elf32_Shdr *sym_sh = &shdrs[symtab_idx];
    uint32_t strtab_idx = sym_sh->sh_link;
    if (strtab_idx >= ehdr.e_shnum) {
        free(shdrs);
        fclose(f);
        return NULL;
    }
    Elf32_Shdr *str_sh = &shdrs[strtab_idx];

    /* Read string table */
    char *strtab = malloc(str_sh->sh_size);
    if (!strtab) { free(shdrs); fclose(f); return NULL; }
    fseek(f, str_sh->sh_offset, SEEK_SET);
    if (fread(strtab, 1, str_sh->sh_size, f) != str_sh->sh_size) {
        free(strtab); free(shdrs); fclose(f); return NULL;
    }

    /* Read raw symbol entries */
    int nsyms = sym_sh->sh_size / sizeof(Elf32_Sym);
    Elf32_Sym *raw = malloc(sym_sh->sh_size);
    if (!raw) { free(strtab); free(shdrs); fclose(f); return NULL; }
    fseek(f, sym_sh->sh_offset, SEEK_SET);
    if (fread(raw, sizeof(Elf32_Sym), nsyms, f) != (size_t)nsyms) {
        free(raw); free(strtab); free(shdrs); fclose(f); return NULL;
    }
    uint32_t strtab_size = str_sh->sh_size;
    fclose(f);
    free(shdrs);

    /* Filter: keep FUNC and OBJECT symbols with nonzero value */
    elf_symbol_t *entries = malloc(nsyms * sizeof(elf_symbol_t));
    if (!entries) { free(raw); free(strtab); return NULL; }

    int count = 0;
    for (int i = 0; i < nsyms; i++) {
        uint8_t type = ELF32_ST_TYPE(raw[i].st_info);
        if (raw[i].st_value == 0) continue;
        if (raw[i].st_name == 0) continue;
        if (raw[i].st_name >= strtab_size) continue;
        if (type != STT_FUNC && type != STT_OBJECT && type != STT_NOTYPE)
            continue;
        entries[count].addr = raw[i].st_value;
        entries[count].size = raw[i].st_size;
        entries[count].name = strtab + raw[i].st_name;
        count++;
    }
    free(raw);

    /* Sort by address */
    qsort(entries, count, sizeof(elf_symbol_t), symbol_cmp);

    elf_symtab_t *tab = calloc(1, sizeof(elf_symtab_t));
    if (!tab) { free(entries); free(strtab); return NULL; }
    tab->entries = entries;
    tab->count = count;
    tab->strtab = strtab;

    if (verbose) {
        printf("Symbols: %d loaded from '%s'\n", count, filename);
    }
    return tab;
}

const char *elf_lookup_symbol(elf_symtab_t *tab, uint32_t addr,
                              uint32_t *offset_out) {
    if (!tab || tab->count == 0) return NULL;

    /* Binary search for the last entry with addr <= target */
    int lo = 0, hi = tab->count - 1, best = -1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        if (tab->entries[mid].addr <= addr) {
            best = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    if (best < 0) return NULL;

    elf_symbol_t *sym = &tab->entries[best];
    uint32_t off = addr - sym->addr;

    /* If symbol has a size, check we're within it */
    if (sym->size > 0 && off >= sym->size) return NULL;
    /* If symbol has no size, allow a reasonable range */
    if (sym->size == 0 && off > 0x10000) return NULL;

    if (offset_out) *offset_out = off;
    return sym->name;
}

uint32_t elf_find_symbol(elf_symtab_t *tab, const char *name) {
    if (!tab || !name) return 0;
    for (int i = 0; i < tab->count; i++) {
        if (strcmp(tab->entries[i].name, name) == 0)
            return tab->entries[i].addr;
    }
    return 0;
}

void elf_free_symbols(elf_symtab_t *tab) {
    if (!tab) return;
    free(tab->entries);
    free(tab->strtab);
    free(tab);
}

/* =========================================================================
 * DWARF .debug_line Parser
 * ========================================================================= */

/* LEB128 decoders */
static uint32_t read_uleb128(const uint8_t **p, const uint8_t *end) {
    uint32_t result = 0;
    int shift = 0;
    while (*p < end) {
        uint8_t byte = *(*p)++;
        result |= (uint32_t)(byte & 0x7F) << shift;
        if (!(byte & 0x80)) break;
        shift += 7;
    }
    return result;
}

static int32_t read_sleb128(const uint8_t **p, const uint8_t *end) {
    int32_t result = 0;
    int shift = 0;
    uint8_t byte;
    do {
        if (*p >= end) break;
        byte = *(*p)++;
        result |= (int32_t)(byte & 0x7F) << shift;
        shift += 7;
    } while (byte & 0x80);
    if (shift < 32 && (byte & 0x40))
        result |= -(1 << shift);
    return result;
}

static uint16_t read16le(const uint8_t **p) {
    uint16_t v = (*p)[0] | ((uint16_t)(*p)[1] << 8);
    *p += 2;
    return v;
}

static uint32_t read32le(const uint8_t **p) {
    uint32_t v = (*p)[0] | ((uint32_t)(*p)[1] << 8) |
                 ((uint32_t)(*p)[2] << 16) | ((uint32_t)(*p)[3] << 24);
    *p += 4;
    return v;
}

/* DWARF line number standard opcodes */
#define DW_LNS_copy             1
#define DW_LNS_advance_pc       2
#define DW_LNS_advance_line     3
#define DW_LNS_set_file         4
#define DW_LNS_set_column       5
#define DW_LNS_negate_stmt      6
#define DW_LNS_set_basic_block  7
#define DW_LNS_const_add_pc     8
#define DW_LNS_fixed_advance_pc 9
#define DW_LNS_set_prologue_end 10
#define DW_LNS_set_epilogue_begin 11

/* DWARF line number extended opcodes */
#define DW_LNE_end_sequence     1
#define DW_LNE_set_address      2
#define DW_LNE_define_file      3

/* Dynamic array for collecting line entries */
typedef struct {
    elf_line_entry_t *data;
    int count;
    int cap;
} line_vec_t;

static void line_vec_push(line_vec_t *v, uint32_t addr, uint16_t file, uint32_t line) {
    if (v->count >= v->cap) {
        v->cap = v->cap ? v->cap * 2 : 4096;
        v->data = realloc(v->data, v->cap * sizeof(elf_line_entry_t));
    }
    v->data[v->count].addr = addr;
    v->data[v->count].file_idx = file;
    v->data[v->count].line = line;
    v->count++;
}

/* Dynamic array for collecting file paths */
typedef struct {
    char **data;
    int count;
    int cap;
} str_vec_t;

static int str_vec_push(str_vec_t *v, const char *s) {
    if (v->count >= v->cap) {
        v->cap = v->cap ? v->cap * 2 : 64;
        v->data = realloc(v->data, v->cap * sizeof(char *));
    }
    v->data[v->count] = strdup(s);
    return v->count++;
}

static int line_entry_cmp(const void *a, const void *b) {
    const elf_line_entry_t *la = (const elf_line_entry_t *)a;
    const elf_line_entry_t *lb = (const elf_line_entry_t *)b;
    if (la->addr < lb->addr) return -1;
    if (la->addr > lb->addr) return 1;
    return 0;
}

/*
 * Find a section by name in the ELF.  Uses .shstrtab.
 * Returns pointer to the section header, or NULL.
 */
static Elf32_Shdr *find_section_by_name(Elf32_Shdr *shdrs, int shnum,
                                         const char *shstrtab, uint32_t shstrtab_size,
                                         const char *name) {
    for (int i = 0; i < shnum; i++) {
        if (shdrs[i].sh_name < shstrtab_size &&
            strcmp(shstrtab + shdrs[i].sh_name, name) == 0)
            return &shdrs[i];
    }
    return NULL;
}

elf_linetab_t *elf_load_lines(const char *filename, int verbose) {
    FILE *f = fopen(filename, "rb");
    if (!f) return NULL;

    Elf32_Ehdr ehdr;
    if (fread(&ehdr, sizeof(ehdr), 1, f) != 1 || ehdr.e_magic != ELF_MAGIC) {
        fclose(f);
        return NULL;
    }
    if (ehdr.e_shoff == 0 || ehdr.e_shnum == 0) {
        fclose(f);
        return NULL;
    }

    /* Read section headers */
    Elf32_Shdr *shdrs = calloc(ehdr.e_shnum, sizeof(Elf32_Shdr));
    if (!shdrs) { fclose(f); return NULL; }
    fseek(f, ehdr.e_shoff, SEEK_SET);
    if (fread(shdrs, sizeof(Elf32_Shdr), ehdr.e_shnum, f) != ehdr.e_shnum) {
        free(shdrs); fclose(f); return NULL;
    }

    /* Read .shstrtab for section name lookup */
    char *shstrtab = NULL;
    uint32_t shstrtab_size = 0;
    if (ehdr.e_shstrndx < ehdr.e_shnum) {
        shstrtab_size = shdrs[ehdr.e_shstrndx].sh_size;
        shstrtab = malloc(shstrtab_size);
        if (shstrtab) {
            fseek(f, shdrs[ehdr.e_shstrndx].sh_offset, SEEK_SET);
            if (fread(shstrtab, 1, shstrtab_size, f) != shstrtab_size) {
                free(shstrtab); shstrtab = NULL; shstrtab_size = 0;
            }
        }
    }
    if (!shstrtab) {
        free(shdrs); fclose(f); return NULL;
    }

    /* Find .debug_line section */
    Elf32_Shdr *dl_sh = find_section_by_name(shdrs, ehdr.e_shnum,
                                              shstrtab, shstrtab_size,
                                              ".debug_line");
    if (!dl_sh || dl_sh->sh_size == 0) {
        free(shstrtab); free(shdrs); fclose(f);
        return NULL;
    }

    /* Read .debug_line section data */
    uint8_t *dl_data = malloc(dl_sh->sh_size);
    if (!dl_data) {
        free(shstrtab); free(shdrs); fclose(f); return NULL;
    }
    fseek(f, dl_sh->sh_offset, SEEK_SET);
    if (fread(dl_data, 1, dl_sh->sh_size, f) != dl_sh->sh_size) {
        free(dl_data); free(shstrtab); free(shdrs); fclose(f); return NULL;
    }
    fclose(f);

    /* Process all compilation units in .debug_line */
    line_vec_t lines = {0};
    str_vec_t dirs = {0};
    str_vec_t files = {0};
    str_vec_push(&files, "<unknown>");  /* file index 0 = unknown */

    const uint8_t *p = dl_data;
    const uint8_t *section_end = dl_data + dl_sh->sh_size;

    while (p < section_end) {
        const uint8_t *cu_start = p;
        uint32_t unit_length = read32le(&p);
        if (unit_length == 0 || unit_length == 0xFFFFFFFF) break;
        const uint8_t *cu_end = cu_start + 4 + unit_length;
        if (cu_end > section_end) break;

        uint16_t version = read16le(&p);
        if (version < 2 || version > 4) { p = cu_end; continue; }

        uint32_t header_length = read32le(&p);
        const uint8_t *program_start = p + header_length;

        uint8_t min_inst_length = *p++;
        if (min_inst_length == 0) min_inst_length = 1;

        /* DWARF4 has max_ops_per_instruction; DWARF2/3 don't */
        uint8_t max_ops_per_inst = 1;
        if (version >= 4) max_ops_per_inst = *p++;
        (void)max_ops_per_inst;

        uint8_t default_is_stmt = *p++;
        int8_t line_base = (int8_t)*p++;
        uint8_t line_range = *p++;
        if (line_range == 0) line_range = 1;
        uint8_t opcode_base = *p++;

        /* Standard opcode lengths */
        const uint8_t *std_opcode_lens = p;
        p += opcode_base - 1;

        /* Include directories (null-terminated strings, ending with empty string) */
        int dir_base = dirs.count;
        str_vec_push(&dirs, ".");  /* dir 0 = compilation directory */
        while (p < program_start && *p != 0) {
            str_vec_push(&dirs, (const char *)p);
            p += strlen((const char *)p) + 1;
        }
        if (p < program_start) p++;  /* skip terminating null */

        /* File names table */
        int file_base = files.count;
        while (p < program_start && *p != 0) {
            const char *name = (const char *)p;
            p += strlen(name) + 1;
            uint32_t dir_idx = read_uleb128(&p, program_start);
            read_uleb128(&p, program_start);  /* time - skip */
            read_uleb128(&p, program_start);  /* size - skip */

            /* Build full path: dir/name */
            char path[512];
            if (dir_idx > 0 && (int)(dir_base + dir_idx) < dirs.count) {
                snprintf(path, sizeof(path), "%s/%s", dirs.data[dir_base + dir_idx], name);
            } else {
                snprintf(path, sizeof(path), "%s", name);
            }
            str_vec_push(&files, path);
        }
        if (p < program_start) p++;  /* skip terminating null */

        p = program_start;

        /* Execute the line number program */
        uint32_t sm_addr = 0;
        uint32_t sm_line = 1;
        uint16_t sm_file = (file_base < files.count) ? (uint16_t)file_base : 0;
        int      sm_is_stmt = default_is_stmt;
        int      sm_end_seq = 0;

        while (p < cu_end) {
            uint8_t op = *p++;
            if (op >= opcode_base) {
                /* Special opcode */
                int adjusted = op - opcode_base;
                int addr_advance = (adjusted / line_range) * min_inst_length;
                int line_advance = line_base + (adjusted % line_range);
                sm_addr += addr_advance;
                sm_line += line_advance;
                line_vec_push(&lines, sm_addr, sm_file, sm_line);
            } else if (op == 0) {
                /* Extended opcode */
                uint32_t ext_len = read_uleb128(&p, cu_end);
                const uint8_t *ext_end = p + ext_len;
                if (ext_end > cu_end) break;
                if (ext_len == 0) continue;
                uint8_t ext_op = *p++;
                switch (ext_op) {
                    case DW_LNE_end_sequence:
                        line_vec_push(&lines, sm_addr, sm_file, sm_line);
                        sm_addr = 0;
                        sm_line = 1;
                        sm_file = (file_base < files.count) ? (uint16_t)file_base : 0;
                        sm_is_stmt = default_is_stmt;
                        sm_end_seq = 0;
                        break;
                    case DW_LNE_set_address:
                        sm_addr = read32le(&p);
                        break;
                    case DW_LNE_define_file: {
                        const char *name = (const char *)p;
                        p += strlen(name) + 1;
                        uint32_t dir_idx = read_uleb128(&p, ext_end);
                        read_uleb128(&p, ext_end);  /* time */
                        read_uleb128(&p, ext_end);  /* size */
                        char path[512];
                        if (dir_idx > 0 && (int)(dir_base + dir_idx) < dirs.count)
                            snprintf(path, sizeof(path), "%s/%s",
                                     dirs.data[dir_base + dir_idx], name);
                        else
                            snprintf(path, sizeof(path), "%s", name);
                        str_vec_push(&files, path);
                        break;
                    }
                    default:
                        break;
                }
                p = ext_end;
            } else {
                /* Standard opcode */
                switch (op) {
                    case DW_LNS_copy:
                        line_vec_push(&lines, sm_addr, sm_file, sm_line);
                        break;
                    case DW_LNS_advance_pc:
                        sm_addr += read_uleb128(&p, cu_end) * min_inst_length;
                        break;
                    case DW_LNS_advance_line:
                        sm_line += read_sleb128(&p, cu_end);
                        break;
                    case DW_LNS_set_file: {
                        uint32_t fidx = read_uleb128(&p, cu_end);
                        /* DWARF file indices are 1-based within the CU's file table */
                        sm_file = (uint16_t)(file_base + fidx - 1);
                        break;
                    }
                    case DW_LNS_set_column:
                        read_uleb128(&p, cu_end);  /* skip column */
                        break;
                    case DW_LNS_negate_stmt:
                        sm_is_stmt = !sm_is_stmt;
                        break;
                    case DW_LNS_set_basic_block:
                        break;
                    case DW_LNS_const_add_pc:
                        sm_addr += ((255 - opcode_base) / line_range) * min_inst_length;
                        break;
                    case DW_LNS_fixed_advance_pc:
                        sm_addr += read16le(&p);
                        break;
                    case DW_LNS_set_prologue_end:
                    case DW_LNS_set_epilogue_begin:
                        break;
                    default:
                        /* Unknown standard opcode: skip its operands */
                        if (op - 1 < opcode_base - 1) {
                            for (uint8_t j = 0; j < std_opcode_lens[op - 1]; j++)
                                read_uleb128(&p, cu_end);
                        }
                        break;
                }
            }
            (void)sm_end_seq;
            (void)sm_is_stmt;
        }
    }

    free(dl_data);
    free(shstrtab);
    free(shdrs);
    /* Free directory strings (files are kept) */
    for (int i = 0; i < dirs.count; i++) free(dirs.data[i]);
    free(dirs.data);

    if (lines.count == 0) {
        for (int i = 0; i < files.count; i++) free(files.data[i]);
        free(files.data);
        free(lines.data);
        return NULL;
    }

    /* Sort by address */
    qsort(lines.data, lines.count, sizeof(elf_line_entry_t), line_entry_cmp);

    elf_linetab_t *tab = calloc(1, sizeof(elf_linetab_t));
    tab->entries = lines.data;
    tab->count = lines.count;
    tab->files = files.data;
    tab->num_files = files.count;

    if (verbose)
        printf("DWARF lines: %d entries, %d files from '%s'\n",
               tab->count, tab->num_files, filename);

    return tab;
}

const char *elf_lookup_line(elf_linetab_t *tab, uint32_t addr, int *line_out) {
    if (!tab || tab->count == 0) return NULL;

    /* Binary search for last entry with addr <= target */
    int lo = 0, hi = tab->count - 1, best = -1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        if (tab->entries[mid].addr <= addr) {
            best = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    if (best < 0) return NULL;

    elf_line_entry_t *e = &tab->entries[best];
    /* Only match if within a reasonable range (64KB) */
    if (addr - e->addr > 0x10000) return NULL;

    if (line_out) *line_out = (int)e->line;

    if (e->file_idx < tab->num_files)
        return tab->files[e->file_idx];
    return NULL;
}

void elf_free_lines(elf_linetab_t *tab) {
    if (!tab) return;
    free(tab->entries);
    for (int i = 0; i < tab->num_files; i++) free(tab->files[i]);
    free(tab->files);
    free(tab);
}
