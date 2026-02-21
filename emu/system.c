/*
 * system.c - M65832 Minimal System Emulation
 *
 * Wires together CPU, memory, and I/O devices.
 */

#include "system.h"
#include "boot_header.h"
#include "sandbox_filesystem.h"
#include "platform.h"
#include "elf_loader.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Forward declarations */
static int system_inject_kernel_to_disk(system_state_t *sys, const char *kernel_file);

/* ============================================================================
 * Configuration
 * ========================================================================= */

void system_config_init(system_config_t *config) {
    if (!config) return;
    
    memset(config, 0, sizeof(*config));
    
    config->ram_size = SYSTEM_DEFAULT_RAM_SIZE;
    config->kernel_file = NULL;
    config->initrd_file = NULL;
    config->cmdline = NULL;
    config->entry_point = 0;
    config->enable_uart = true;
    config->uart_raw_mode = false;
    config->enable_blkdev = true;
    config->disk_file = NULL;
    config->disk_readonly = false;
    config->bootrom_file = NULL;
    config->supervisor_mode = true;
    config->native32_mode = true;
    config->verbose = false;
    config->sandbox_root = NULL;
    config->syscall_user = NULL;
    config->syscall_handler = NULL;
}

/* ============================================================================
 * Syscall Return Handling
 * ========================================================================= */

static uint8_t system_pull8(m65832_cpu_t *cpu) {
    if (IS_EMU(cpu)) {
        cpu->s = 0x100 | ((cpu->s + 1) & 0xFF);
        return cpu->memory[0x100 + (cpu->s & 0xFF)];
    }
    cpu->s++;
    return m65832_emu_read8(cpu, cpu->s);
}

static void system_rti(m65832_cpu_t *cpu) {
    uint8_t p_lo = system_pull8(cpu);
    uint8_t p_hi = system_pull8(cpu);
    cpu->p = (uint16_t)p_lo | ((uint16_t)p_hi << 8);
    uint8_t pc0 = system_pull8(cpu);
    uint8_t pc1 = system_pull8(cpu);
    uint8_t pc2 = system_pull8(cpu);
    uint8_t pc3 = system_pull8(cpu);
    cpu->pc = (uint32_t)pc0 | ((uint32_t)pc1 << 8) |
              ((uint32_t)pc2 << 16) | ((uint32_t)pc3 << 24);
}

static bool system_handle_syscall(system_state_t *sys, uint8_t trap_code) {
    if (sys->syscall_handler) {
        return sys->syscall_handler(sys, trap_code, sys->syscall_user);
    }
    return sandbox_fs_handle_syscall(sys, trap_code);
}

/* ============================================================================
 * File Loading Utilities
 * ========================================================================= */

static int load_binary_file(m65832_cpu_t *cpu, const char *filename, 
                            uint32_t addr, bool verbose) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        fprintf(stderr, "error: cannot open '%s'\n", filename);
        return -1;
    }
    
    /* Get file size */
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    if (size <= 0) {
        fprintf(stderr, "error: empty file '%s'\n", filename);
        fclose(f);
        return -1;
    }
    
    /* Check bounds */
    size_t mem_size = m65832_emu_get_memory_size(cpu);
    if (addr + size > mem_size) {
        fprintf(stderr, "error: file too large for memory (0x%X + %ld > %zu)\n",
                addr, size, mem_size);
        fclose(f);
        return -1;
    }
    
    /* Load file */
    uint8_t *mem = m65832_emu_get_memory_ptr(cpu);
    if (!mem) {
        fprintf(stderr, "error: cannot get memory pointer\n");
        fclose(f);
        return -1;
    }
    
    size_t read = fread(mem + addr, 1, size, f);
    fclose(f);
    
    if (read != (size_t)size) {
        fprintf(stderr, "error: short read from '%s'\n", filename);
        return -1;
    }
    
    if (verbose) {
        printf("Loaded %ld bytes from '%s' at 0x%08X\n", size, filename, addr);
    }
    
    return (int)size;
}

/* ============================================================================
 * System Initialization
 * ========================================================================= */

system_state_t *system_init(const system_config_t *config) {
    if (!config) return NULL;
    
    system_state_t *sys = calloc(1, sizeof(system_state_t));
    if (!sys) {
        fprintf(stderr, "error: cannot allocate system state\n");
        return NULL;
    }
    
    /* Copy configuration */
    sys->config = *config;
    sys->syscall_handler = config->syscall_handler;
    sys->syscall_user = config->syscall_user;
    
    /* Create CPU */
    sys->cpu = m65832_emu_init(config->ram_size);
    if (!sys->cpu) {
        fprintf(stderr, "error: cannot create CPU\n");
        free(sys);
        return NULL;
    }
    
    if (config->verbose) {
        printf("System: %zu MB RAM\n", config->ram_size / (1024 * 1024));
    }

    sandbox_fs_init(sys, config->sandbox_root);
    
    const platform_config_t *platform = platform_get_config(platform_get_default());

    /* Initialize UART */
    if (config->enable_uart) {
        sys->uart = uart_init(sys->cpu, platform);
        if (!sys->uart) {
            fprintf(stderr, "error: cannot initialize UART\n");
            m65832_emu_close(sys->cpu);
            free(sys);
            return NULL;
        }
        
        if (config->uart_raw_mode) {
            uart_set_raw_mode(sys->uart, true);
        }
        
        if (config->verbose) {
            printf("System: UART at 0x%08X\n", platform->uart_base);
        }
    }
    
    /* Initialize block device */
    if (config->enable_blkdev) {
        sys->blkdev = blkdev_init(sys->cpu, platform, config->disk_file, config->disk_readonly);
        if (!sys->blkdev) {
            fprintf(stderr, "error: cannot initialize block device\n");
            if (sys->uart) uart_destroy(sys->uart);
            m65832_emu_close(sys->cpu);
            free(sys);
            return NULL;
        }
        
        if (config->verbose) {
            printf("System: Block device at 0x%08X", platform->sd_base);
            if (config->disk_file) {
                printf(" (%s, %llu sectors)\n", 
                       config->disk_file, 
                       (unsigned long long)blkdev_get_capacity(sys->blkdev));
            } else {
                printf(" (no media)\n");
            }
        }
    }
    
    /* Load boot ROM if specified */
    if (config->bootrom_file) {
        sys->bootrom = bootrom_load(sys->cpu, config->bootrom_file,
                                    SYSTEM_BOOT_ROM, SYSTEM_BOOT_ROM_SIZE,
                                    config->verbose);
        if (!sys->bootrom) {
            fprintf(stderr, "error: cannot load boot ROM '%s'\n", config->bootrom_file);
            system_destroy(sys);
            return NULL;
        }
    }
    
    /* Initialize boot parameters */
    memset(&sys->boot_params, 0, sizeof(sys->boot_params));
    sys->boot_params.magic = BOOT_PARAMS_MAGIC;
    sys->boot_params.version = BOOT_PARAMS_VERSION;
    sys->boot_params.mem_base = 0;
    sys->boot_params.mem_size = (uint32_t)config->ram_size;
    sys->boot_params.uart_base = config->enable_uart ? platform->uart_base : 0;
    sys->boot_params.timer_base = SYSREG_TIMER_CTRL;
    
    /* Load kernel if specified */
    if (config->kernel_file) {
        if (sys->bootrom) {
            /*
             * Boot ROM mode: kernel goes into the disk image.
             * If --kernel is a raw binary or ELF, inject it into the
             * block device disk image at the standard kernel sector.
             * The boot ROM will load it via DMA at runtime.
             */
            int size = system_inject_kernel_to_disk(sys, config->kernel_file);
            if (size < 0) {
                system_destroy(sys);
                return NULL;
            }
        } else {
            /* Legacy mode: load kernel directly into RAM */
            int size = system_load_kernel(sys, config->kernel_file, 0);
            if (size < 0) {
                system_destroy(sys);
                return NULL;
            }
        }
    }
    
    /* Load initrd if specified */
    if (config->initrd_file) {
        int size = system_load_initrd(sys, config->initrd_file, 0);
        if (size < 0) {
            system_destroy(sys);
            return NULL;
        }
    }
    
    /* Set command line */
    if (config->cmdline && strlen(config->cmdline) > 0) {
        uint32_t cmdline_addr = SYSTEM_BOOT_PARAMS + sizeof(boot_params_t);
        size_t cmdline_len = strlen(config->cmdline);
        m65832_emu_write_block(sys->cpu, cmdline_addr, 
                               config->cmdline, cmdline_len + 1);
        sys->boot_params.cmdline_addr = cmdline_addr;
        sys->boot_params.cmdline_size = (uint32_t)cmdline_len;
    }
    
    /* Write boot parameters */
    system_write_boot_params(sys);
    
    /* Reset CPU */
    m65832_emu_reset(sys->cpu);
    
    /* Configure CPU mode */
    if (config->native32_mode) {
        m65832_emu_enter_native32(sys->cpu);
    }
    
    if (config->supervisor_mode) {
        /* Set supervisor flag */
        uint16_t p = m65832_get_p(sys->cpu);
        p |= P_S;
        m65832_set_p(sys->cpu, p);
    }
    
    /* Set entry point */
    if (sys->bootrom) {
        /* Boot ROM mode: CPU starts at boot ROM entry point */
        uint32_t rom_entry = config->entry_point;
        if (rom_entry == 0) {
            rom_entry = bootrom_get_entry(sys->bootrom);
        }
        if (rom_entry != 0) {
            m65832_set_pc(sys->cpu, rom_entry);
        }
    } else {
        /* Legacy mode: explicit > ELF > default kernel load address */
        uint32_t entry = config->entry_point;
        if (entry == 0 && sys->elf_entry != 0) {
            entry = sys->elf_entry;
        }
        if (entry == 0 && config->kernel_file) {
            entry = SYSTEM_KERNEL_LOAD;
        }
        if (entry != 0) {
            m65832_set_pc(sys->cpu, entry);
        }
    }
    
    /* Configure polling interval */
    sys->poll_interval = 1000;  /* Poll every 1000 instructions */
    sys->poll_counter = 0;
    sys->running = false;
    
    return sys;
}

void system_destroy(system_state_t *sys) {
    if (!sys) return;
    
    /* Destroy devices */
    if (sys->bootrom) {
        bootrom_destroy(sys->bootrom);
    }
    if (sys->blkdev) {
        blkdev_destroy(sys->blkdev);
    }
    if (sys->uart) {
        uart_destroy(sys->uart);
    }
    
    /* Clean up temporary disk image */
    if (sys->tmp_disk_path) {
        unlink(sys->tmp_disk_path);
        free(sys->tmp_disk_path);
    }
    
    /* Destroy CPU */
    if (sys->cpu) {
        m65832_emu_close(sys->cpu);
    }

    sandbox_fs_cleanup(sys);
    
    free(sys);
}

/* ============================================================================
 * System Control
 * ========================================================================= */

void system_reset(system_state_t *sys) {
    if (!sys || !sys->cpu) return;
    
    m65832_emu_reset(sys->cpu);
    
    /* Restore mode configuration */
    if (sys->config.native32_mode) {
        m65832_emu_enter_native32(sys->cpu);
    }
    
    if (sys->config.supervisor_mode) {
        uint16_t p = m65832_get_p(sys->cpu);
        p |= P_S;
        m65832_set_p(sys->cpu, p);
    }
    
    /* Restore entry point */
    uint32_t entry = sys->config.entry_point;
    if (entry == 0 && sys->config.kernel_file) {
        entry = SYSTEM_KERNEL_LOAD;
    }
    if (entry != 0) {
        m65832_set_pc(sys->cpu, entry);
    }
}

uint64_t system_run(system_state_t *sys, uint64_t cycles) {
    if (!sys || !sys->cpu) return 0;
    
    sys->running = true;
    uint64_t total = 0;
    uint64_t target = cycles > 0 ? cycles : UINT64_MAX;
    
    while (sys->running && total < target && m65832_emu_is_running(sys->cpu)) {
        int c = m65832_emu_step(sys->cpu);
        if (c < 0) break;
        total += c;

        /* Handle syscalls */
        if (sys->cpu->trap == TRAP_SYSCALL) {
            bool handled = false;
            handled = system_handle_syscall(sys, (uint8_t)sys->cpu->trap_addr);
            if (handled) {
                sys->cpu->trap = TRAP_NONE;
                sys->cpu->trap_addr = 0;
                system_rti(sys->cpu);
            } else {
                if (sys->config.verbose) {
                    printf("Unhandled syscall trap at %08X\n", sys->cpu->trap_addr);
                }
                break;
            }
        }
        
        /* Stop on BRK trap - the program has crashed or hit an unhandled exception */
        if (sys->cpu->trap == TRAP_BRK) {
            break;
        }
        
        /* Poll devices periodically */
        sys->poll_counter++;
        if (sys->poll_counter >= sys->poll_interval) {
            system_poll_devices(sys);
            sys->poll_counter = 0;
        }
        
        /* Handle device IRQs */
        bool irq = false;
        if (sys->uart && uart_irq_pending(sys->uart)) {
            irq = true;
        }
        if (sys->blkdev && blkdev_irq_pending(sys->blkdev)) {
            irq = true;
        }
        if (irq) {
            m65832_irq(sys->cpu, true);
        }
    }
    
    sys->running = false;
    return total;
}

void system_run_until_halt(system_state_t *sys) {
    system_run(sys, 0);
}

void system_set_syscall_handler(system_state_t *sys,
                                bool (*handler)(system_state_t *sys, uint8_t trap_code, void *user),
                                void *user) {
    if (!sys) return;
    sys->syscall_handler = handler;
    sys->syscall_user = user;
}

void system_stop(system_state_t *sys) {
    if (sys) {
        sys->running = false;
        if (sys->cpu) {
            m65832_stop(sys->cpu);
        }
    }
}

bool system_is_running(system_state_t *sys) {
    return sys && sys->running && sys->cpu && m65832_emu_is_running(sys->cpu);
}

void system_poll_devices(system_state_t *sys) {
    if (!sys) return;
    
    /* Poll UART for input */
    if (sys->uart) {
        uart_poll(sys->uart);
    }
    
    /* Block device uses synchronous DMA, no polling needed */
    /* Future: poll network, etc. */
}

/* ============================================================================
 * Loading
 * ========================================================================= */

/*
 * Inject a kernel binary into a temporary disk image and attach it to the
 * block device. Called when both --bootrom and --kernel are specified.
 * The boot ROM will then load the kernel from the disk via DMA.
 */
static int system_inject_kernel_to_disk(system_state_t *sys, const char *kernel_file) {
    if (!sys || !sys->cpu || !kernel_file) return -1;
    
    /* Read kernel file */
    FILE *kf = fopen(kernel_file, "rb");
    if (!kf) {
        fprintf(stderr, "error: cannot open kernel '%s'\n", kernel_file);
        return -1;
    }
    
    fseek(kf, 0, SEEK_END);
    long kernel_size = ftell(kf);
    fseek(kf, 0, SEEK_SET);
    
    if (kernel_size <= 0) {
        fprintf(stderr, "error: empty kernel file '%s'\n", kernel_file);
        fclose(kf);
        return -1;
    }
    
    /* If this is an ELF file, reject it -- must use vmlinux.bin */
    uint32_t magic = 0;
    if (fread(&magic, 1, 4, kf) == 4 && magic == 0x464C457F) {
        fprintf(stderr, "error: kernel file '%s' is an ELF.\n", kernel_file);
        fprintf(stderr, "  With boot ROM mode, use a flat binary (vmlinux.bin).\n");
        fprintf(stderr, "  Build it with: make -C linux-m65832 vmlinux.bin\n");
        fclose(kf);
        return -1;
    }
    fseek(kf, 0, SEEK_SET);
    
    uint8_t *kernel_data = malloc(kernel_size);
    if (!kernel_data) {
        fprintf(stderr, "error: cannot allocate %ld bytes for kernel\n", kernel_size);
        fclose(kf);
        return -1;
    }
    
    if (fread(kernel_data, 1, kernel_size, kf) != (size_t)kernel_size) {
        fprintf(stderr, "error: short read from kernel '%s'\n", kernel_file);
        free(kernel_data);
        fclose(kf);
        return -1;
    }
    fclose(kf);
    
    /* Calculate disk image size: header + kernel with room to spare */
    uint32_t kernel_sectors = (kernel_size + BOOT_SECTOR_SIZE - 1) / BOOT_SECTOR_SIZE;
    uint64_t disk_sectors = BOOT_KERNEL_SECTOR + kernel_sectors + 1024; /* Extra space */
    uint64_t disk_size = disk_sectors * BOOT_SECTOR_SIZE;
    
    /* Create temporary disk image */
    char tmp_path[] = "/tmp/m65832_boot_XXXXXX";
    int tmp_fd = mkstemp(tmp_path);
    if (tmp_fd < 0) {
        fprintf(stderr, "error: cannot create temporary disk image\n");
        free(kernel_data);
        return -1;
    }
    
    /* Extend to full size */
    if (ftruncate(tmp_fd, disk_size) != 0) {
        fprintf(stderr, "error: cannot extend temporary disk image\n");
        close(tmp_fd);
        unlink(tmp_path);
        free(kernel_data);
        return -1;
    }
    
    /* Write boot header at sector 0 */
    boot_header_t header;
    memset(&header, 0, sizeof(header));
    header.magic = BOOT_HEADER_MAGIC;
    header.version = BOOT_HEADER_VERSION;
    header.kernel_sector = BOOT_KERNEL_SECTOR;
    header.kernel_size = (uint32_t)kernel_size;
    header.kernel_load_addr = BOOT_KERNEL_LOAD_ADDR;
    header.kernel_entry_offset = 0;
    header.flags = 0;
    
    lseek(tmp_fd, 0, SEEK_SET);
    if (write(tmp_fd, &header, sizeof(header)) != sizeof(header)) {
        fprintf(stderr, "error: cannot write boot header\n");
        close(tmp_fd);
        unlink(tmp_path);
        free(kernel_data);
        return -1;
    }
    
    /* Write kernel at sector BOOT_KERNEL_SECTOR */
    off_t kernel_offset = (off_t)BOOT_KERNEL_SECTOR * BOOT_SECTOR_SIZE;
    lseek(tmp_fd, kernel_offset, SEEK_SET);
    if (write(tmp_fd, kernel_data, kernel_size) != kernel_size) {
        fprintf(stderr, "error: cannot write kernel to disk image\n");
        close(tmp_fd);
        unlink(tmp_path);
        free(kernel_data);
        return -1;
    }
    
    close(tmp_fd);
    free(kernel_data);
    
    /* Save path for cleanup */
    sys->tmp_disk_path = strdup(tmp_path);
    
    /* Attach the disk image to the block device */
    if (sys->blkdev) {
        if (!blkdev_attach(sys->blkdev, tmp_path, false)) {
            fprintf(stderr, "error: cannot attach boot disk image\n");
            return -1;
        }
    } else {
        fprintf(stderr, "error: block device not initialized (needed for boot ROM mode)\n");
        return -1;
    }
    
    /* Update boot params with kernel info */
    sys->boot_params.kernel_start = BOOT_KERNEL_LOAD_ADDR;
    sys->boot_params.kernel_size = (uint32_t)kernel_size;
    
    if (sys->config.verbose) {
        printf("Boot disk: %s (%llu sectors, kernel %ld bytes at sector %u)\n",
               tmp_path, (unsigned long long)disk_sectors,
               kernel_size, BOOT_KERNEL_SECTOR);
    }
    
    return (int)kernel_size;
}

int system_load_kernel(system_state_t *sys, const char *filename, uint32_t addr) {
    if (!sys || !sys->cpu || !filename) return -1;
    
    /* Auto-detect ELF format */
    if (elf_is_elf_file(filename)) {
        uint32_t entry = elf_load(sys->cpu, filename, sys->config.verbose);
        if (entry == 0) return -1;
        
        /* ELF provides its own load addresses and entry point */
        sys->boot_params.kernel_start = entry;
        sys->elf_entry = entry;
        return 1;  /* Success (actual size tracked by ELF loader) */
    }
    
    /* Fall back to raw binary loading */
    if (addr == 0) {
        addr = SYSTEM_KERNEL_LOAD;
    }
    
    int size = load_binary_file(sys->cpu, filename, addr, sys->config.verbose);
    if (size > 0) {
        sys->boot_params.kernel_start = addr;
        sys->boot_params.kernel_size = (uint32_t)size;
    }
    
    return size;
}

int system_load_initrd(system_state_t *sys, const char *filename, uint32_t addr) {
    if (!sys || !sys->cpu || !filename) return -1;
    
    if (addr == 0) {
        addr = SYSTEM_INITRD_LOAD;
    }
    
    int size = load_binary_file(sys->cpu, filename, addr, sys->config.verbose);
    if (size > 0) {
        sys->boot_params.initrd_start = addr;
        sys->boot_params.initrd_size = (uint32_t)size;
    }
    
    return size;
}

void system_write_boot_params(system_state_t *sys) {
    if (!sys || !sys->cpu) return;
    
    m65832_emu_write_block(sys->cpu, SYSTEM_BOOT_PARAMS,
                           &sys->boot_params, sizeof(sys->boot_params));
}

/* ============================================================================
 * Accessors
 * ========================================================================= */

m65832_cpu_t *system_get_cpu(system_state_t *sys) {
    return sys ? sys->cpu : NULL;
}

void system_print_info(system_state_t *sys) {
    if (!sys) return;
    
    printf("M65832 System Configuration:\n");
    printf("  RAM:          %zu MB\n", sys->config.ram_size / (1024 * 1024));
    const platform_config_t *platform = platform_get_config(platform_get_default());
    printf("  UART:         %s at 0x%08X\n", 
           sys->uart ? "enabled" : "disabled", platform->uart_base);
    printf("  Block device: %s at 0x%08X\n",
           sys->blkdev ? "enabled" : "disabled", platform->sd_base);
    if (sys->blkdev && blkdev_get_capacity(sys->blkdev) > 0) {
        uint64_t cap_mb = blkdev_get_capacity_bytes(sys->blkdev) / (1024 * 1024);
        printf("    Disk:       %llu MB (%llu sectors)\n",
               (unsigned long long)cap_mb,
               (unsigned long long)blkdev_get_capacity(sys->blkdev));
    }
    printf("  Timer:        0x%08X\n", SYSREG_TIMER_CTRL);
    
    if (sys->boot_params.kernel_size > 0) {
        printf("  Kernel:       0x%08X (%u bytes)\n",
               sys->boot_params.kernel_start, sys->boot_params.kernel_size);
    }
    if (sys->boot_params.initrd_size > 0) {
        printf("  initrd:       0x%08X (%u bytes)\n",
               sys->boot_params.initrd_start, sys->boot_params.initrd_size);
    }
    if (sys->boot_params.cmdline_size > 0) {
        printf("  cmdline:      0x%08X (%u bytes)\n",
               sys->boot_params.cmdline_addr, sys->boot_params.cmdline_size);
    }
    
    printf("  Entry point:  0x%08X\n", m65832_get_pc(sys->cpu));
    printf("  Mode:         %s, %s\n",
           m65832_flag_e(sys->cpu) ? "emulation" : "native",
           m65832_flag_s(sys->cpu) ? "supervisor" : "user");
}
