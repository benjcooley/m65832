/*
 * platform.c - M65832 Platform Selection
 */

#include "platform.h"
#include <stdio.h>
#include <string.h>
#include <strings.h>

/* Platform configuration table */
static const platform_config_t *g_platforms[PLATFORM_COUNT] = {
    &platform_de25_config,
    &platform_kv260_config,
};

const platform_config_t *platform_get_config(platform_id_t id) {
    if (id >= PLATFORM_COUNT) {
        return &platform_de25_config;  /* Default */
    }
    return g_platforms[id];
}

platform_id_t platform_get_by_name(const char *name) {
    if (!name) return PLATFORM_DE25;
    
    /* Case-insensitive comparison */
    if (strcasecmp(name, "de25") == 0 || 
        strcasecmp(name, "de2-115") == 0 ||
        strcasecmp(name, "de2115") == 0 || 
        strcasecmp(name, "de2_115") == 0) {
        return PLATFORM_DE25;
    }
    
    if (strcasecmp(name, "kv260") == 0 || 
        strcasecmp(name, "kria") == 0) {
        return PLATFORM_KV260;
    }
    
    /* Unknown - default to DE25 */
    fprintf(stderr, "warning: unknown platform '%s', using de25\n", name);
    return PLATFORM_DE25;
}

platform_id_t platform_get_default(void) {
    return PLATFORM_DE25;
}

void platform_list_all(void) {
    printf("Supported platforms:\n");
    for (int i = 0; i < PLATFORM_COUNT; i++) {
        const platform_config_t *p = g_platforms[i];
        printf("  %-12s  %s\n", p->name, p->description);
        printf("                CPU: %u MHz, RAM: %u MB\n",
               p->cpu_freq / 1000000,
               p->ram_size / (1024 * 1024));
    }
    printf("\n");
    printf("Platform aliases:\n");
    printf("  de2-115, de2115, de2_115  -> de25\n");
    printf("  kria                      -> kv260\n");
}
