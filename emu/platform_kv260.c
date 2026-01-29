/*
 * platform_kv260.c - KV260 Platform Configuration
 */

#include "platform.h"
#include "platform_kv260.h"

const platform_config_t platform_kv260_config = {
    .id = PLATFORM_KV260,
    .name = "kv260",
    .description = "AMD/Xilinx Kria KV260 (Zynq UltraScale+)",
    
    .ram_base = KV260_RAM_BASE,
    .ram_size = KV260_RAM_SIZE,
    .boot_rom_base = KV260_BOOT_ROM_BASE,
    .boot_rom_size = KV260_BOOT_ROM_SIZE,
    
    .cpu_freq = KV260_CPU_FREQ,
    .timer_freq = KV260_TIMER_FREQ,
    .uart_freq = KV260_UART_FREQ,
    
    .uart_base = KV260_UART_BASE,
    .sd_base = KV260_SD_BASE,
    .intc_base = KV260_INTC_BASE,
    .timer_base = KV260_SYSTIMER_CTRL,
    .gpio_base = KV260_GPIO_BASE,
    .spi_base = KV260_SPI_BASE,
    .i2c_base = KV260_I2C_BASE,
    
    .sysreg_base = KV260_SYSREG_BASE,
    
    .has_sd_card = true,
    .has_ethernet = true,
    .has_hdmi = true,
    .has_vga = false,
};
