/*
 * platform_de25.c - DE2-115 Platform Configuration
 */

#include "platform.h"
#include "platform_de25.h"

const platform_config_t platform_de25_config = {
    .id = PLATFORM_DE25,
    .name = "de25",
    .description = "Terasic DE2-115 (Cyclone IV EP4CE115)",
    
    .ram_base = DE25_RAM_BASE,
    .ram_size = DE25_RAM_SIZE,
    .boot_rom_base = DE25_BOOT_ROM_BASE,
    .boot_rom_size = DE25_BOOT_ROM_SIZE,
    
    .cpu_freq = DE25_CPU_FREQ,
    .timer_freq = DE25_TIMER_FREQ,
    .uart_freq = DE25_UART_FREQ,
    
    .uart_base = DE25_UART_BASE,
    .sd_base = DE25_SD_BASE,
    .intc_base = DE25_INTC_BASE,
    .timer_base = DE25_SYSTIMER_CTRL,
    .gpio_base = DE25_GPIO_BASE,
    .spi_base = DE25_SPI_BASE,
    .i2c_base = DE25_I2C_BASE,
    
    .sysreg_base = DE25_SYSREG_BASE,
    
    .has_sd_card = true,
    .has_ethernet = false,
    .has_hdmi = false,
    .has_vga = true,
};
