// Test: generic___ffs - find first set bit
// Returns result in A register via STP
// Uses UART at 0xFFFFF100 for debug output (system mode memory map)

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

// Exact copy of the kernel's generic___ffs (BITS_PER_LONG == 32)
static __attribute__((noinline)) unsigned int my_ffs(unsigned long word)
{
    unsigned int num = 0;

    if ((word & 0xffff) == 0) {
        num += 16;
        word >>= 16;
    }
    if ((word & 0xff) == 0) {
        num += 8;
        word >>= 8;
    }
    if ((word & 0xf) == 0) {
        num += 4;
        word >>= 4;
    }
    if ((word & 0x3) == 0) {
        num += 2;
        word >>= 2;
    }
    if ((word & 0x1) == 0)
        num += 1;
    return num;
}

int main(void)
{
    unsigned int result;
    int fail = 0;

    puts("=== Testing __ffs ===\r\n");

    // Test 1: ffs(1) should be 0
    result = my_ffs(1);
    puts("ffs(1)="); puthex(result); puts(" expect 0\r\n");
    if (result != 0) { fail = 1; goto done; }

    // Test 2: ffs(2) should be 1
    result = my_ffs(2);
    puts("ffs(2)="); puthex(result); puts(" expect 1\r\n");
    if (result != 1) { fail = 2; goto done; }

    // Test 3: ffs(4) should be 2
    result = my_ffs(4);
    puts("ffs(4)="); puthex(result); puts(" expect 2\r\n");
    if (result != 2) { fail = 3; goto done; }

    // Test 4: ffs(0x80) should be 7
    result = my_ffs(0x80);
    puts("ffs(0x80)="); puthex(result); puts(" expect 7\r\n");
    if (result != 7) { fail = 4; goto done; }

    // Test 5: ffs(0x100) should be 8
    result = my_ffs(0x100);
    puts("ffs(0x100)="); puthex(result); puts(" expect 8\r\n");
    if (result != 8) { fail = 5; goto done; }

    // Test 6: ffs(0x10000) should be 16
    result = my_ffs(0x10000);
    puts("ffs(0x10000)="); puthex(result); puts(" expect 16\r\n");
    if (result != 16) { fail = 6; goto done; }

    // Test 7: ffs(0x80000000) should be 31
    result = my_ffs(0x80000000u);
    puts("ffs(0x80000000)="); puthex(result); puts(" expect 31\r\n");
    if (result != 31) { fail = 7; goto done; }

    // Test 8: ffs(0xFF) should be 0
    result = my_ffs(0xFF);
    puts("ffs(0xFF)="); puthex(result); puts(" expect 0\r\n");
    if (result != 0) { fail = 8; goto done; }

    // Test 9: ffs(0xFFFF0000) should be 16
    result = my_ffs(0xFFFF0000u);
    puts("ffs(0xFFFF0000)="); puthex(result); puts(" expect 16\r\n");
    if (result != 16) { fail = 9; goto done; }

    puts("\r\nAll tests passed!\r\n");

done:
    if (fail) {
        puts("\r\nFAILED test "); puthex(fail); puts("\r\n");
    }
    return fail;
}
