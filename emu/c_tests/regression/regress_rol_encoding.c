// Test: __clear_bit - the pattern used in init_rt_rq
// Tests AND-store pattern: *p &= ~(1UL << bit)

#define UART_DATA    (*(volatile unsigned int *)0x10006000)
#define UART_STATUS  (*(volatile unsigned int *)0x10006004)
#define UART_TXRDY   0x02

static void putc(char c) {
    while (!(UART_STATUS & UART_TXRDY))
        ;
    UART_DATA = c;
}
static void puts(const char *s) { while (*s) putc(*s++); }
static void puthex(unsigned int v) {
    static const char hex[] = "0123456789abcdef";
    putc('0'); putc('x');
    for (int i = 28; i >= 0; i -= 4)
        putc(hex[(v >> i) & 0xf]);
}

static __attribute__((noinline)) void my_clear_bit(unsigned long nr, unsigned long *addr)
{
    unsigned long mask = 1UL << (nr % 32);
    unsigned long *p = addr + (nr / 32);
    *p &= ~mask;
}

static __attribute__((noinline)) void my_set_bit(unsigned long nr, unsigned long *addr)
{
    unsigned long mask = 1UL << (nr % 32);
    unsigned long *p = addr + (nr / 32);
    *p |= mask;
}

// Simulate init_rt_rq loop pattern
struct list_head {
    struct list_head *next, *prev;
};

#define MAX_PRIO 8  // small for testing

struct prio_array {
    unsigned long bitmap[1];
    struct list_head queue[MAX_PRIO];
};

static __attribute__((noinline)) void init_array(struct prio_array *array)
{
    int i;
    for (i = 0; i < MAX_PRIO; i++) {
        array->queue[i].next = &array->queue[i];
        array->queue[i].prev = &array->queue[i];
        my_clear_bit(i, array->bitmap);
    }
    my_set_bit(MAX_PRIO, array->bitmap);
}

int main(void)
{
    unsigned long bitmap[2] = { 0xFFFFFFFF, 0xFFFFFFFF };
    struct prio_array array;

    puts("=== Test clear_bit ===\r\n");

    // Test 1: clear bit 0
    my_clear_bit(0, bitmap);
    puts("clear(0): "); puthex(bitmap[0]); puts(" expect 0xFFFFFFFE\r\n");
    if (bitmap[0] != 0xFFFFFFFE) { puts("FAIL\r\n"); return 1; }

    // Test 2: clear bit 7
    my_clear_bit(7, bitmap);
    puts("clear(7): "); puthex(bitmap[0]); puts(" expect 0xFFFFFF7E\r\n");
    if (bitmap[0] != 0xFFFFFF7E) { puts("FAIL\r\n"); return 2; }

    // Test 3: clear bit 31
    my_clear_bit(31, bitmap);
    puts("clear(31): "); puthex(bitmap[0]); puts(" expect 0x7FFFFF7E\r\n");
    if (bitmap[0] != 0x7FFFFF7E) { puts("FAIL\r\n"); return 3; }

    // Test 4: set bit 0
    bitmap[0] = 0;
    my_set_bit(0, bitmap);
    puts("set(0): "); puthex(bitmap[0]); puts(" expect 0x00000001\r\n");
    if (bitmap[0] != 0x00000001) { puts("FAIL\r\n"); return 4; }

    // Test 5: init_array pattern
    puts("\r\n=== Test init_array ===\r\n");
    // Match init_rt_rq-style empty bitmap initialization: clear bits are no-ops,
    // then delimiter bit MAX_PRIO is set.
    array.bitmap[0] = 0;
    init_array(&array);
    puts("bitmap: "); puthex(array.bitmap[0]); puts(" expect 0x00000100\r\n");
    if (array.bitmap[0] != 0x00000100) { puts("FAIL\r\n"); return 5; }

    puts("\r\nAll tests passed!\r\n");
    return 0;
}
