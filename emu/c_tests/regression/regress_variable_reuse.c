// Test: Isolate pcpu_alloc_first_chunk volatile workaround bug
// The variable alloc_size is reused multiple times for different allocations.
// Without volatile, the compiler produces a garbage value on later reuses.
//
// Expected: all alloc_size values are small (< 4096)
// Bug: without volatile, one of them becomes ~2GB (0x83f77a20)

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

// Simulate the struct sizes from the kernel
#define PAGE_SIZE 4096
#define PAGE_SHIFT 12
#define PAGE_MASK (~(PAGE_SIZE - 1))
#define SMP_CACHE_BYTES 64
#define PCPU_MIN_ALLOC_SIZE 4
#define BITS_PER_LONG 32
#define BITS_TO_LONGS(nr) (((nr) + BITS_PER_LONG - 1) / BITS_PER_LONG)
#define ALIGN_VAL(x, a) (((x) + (a) - 1) & ~((a) - 1))

// Fake struct to get realistic sizes
struct fake_chunk {
    void *base_addr;
    int start_offset;
    int end_offset;
    int nr_pages;
    int free_bytes;
    unsigned long *alloc_map;
    unsigned long *bound_map;
    void *md_blocks;
    unsigned long populated[1]; // flexible array
};

// Simulate memblock_alloc - just return a fake address and print size
static unsigned int alloc_counter = 0x80100000;
static void *fake_memblock_alloc(unsigned int size, int align) {
    unsigned int addr = ALIGN_VAL(alloc_counter, align);
    alloc_counter = addr + size;
    return (void *)addr;
}

// WITHOUT volatile - reproduces the bug
static __attribute__((noinline)) int test_without_volatile(
    unsigned long tmp_addr, int map_size)
{
    unsigned long aligned_addr;
    int start_offset, region_size, region_bits;
    /*no volatile*/ unsigned int alloc_size;

    aligned_addr = tmp_addr & PAGE_MASK;
    start_offset = tmp_addr - aligned_addr;
    region_size = ALIGN_VAL(start_offset + map_size, PAGE_SIZE);

    // First use of alloc_size
    alloc_size = sizeof(struct fake_chunk) +
                 BITS_TO_LONGS(region_size >> PAGE_SHIFT) * sizeof(unsigned long);
    puts("  alloc1="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    int nr_pages = region_size >> PAGE_SHIFT;
    region_bits = (nr_pages * PAGE_SIZE) / PCPU_MIN_ALLOC_SIZE;

    // Second use of alloc_size
    alloc_size = BITS_TO_LONGS(region_bits) * sizeof(unsigned long);
    puts("  alloc2="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    // Third use of alloc_size
    alloc_size = BITS_TO_LONGS(region_bits + 1) * sizeof(unsigned long);
    puts("  alloc3="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    // Fourth use of alloc_size
    alloc_size = (region_size / (PAGE_SIZE * 2)) * 24; // md_blocks approx
    puts("  alloc4="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    // Check if any alloc_size was unreasonably large
    return 0;
}

// WITH volatile - workaround
static __attribute__((noinline)) int test_with_volatile(
    unsigned long tmp_addr, int map_size)
{
    unsigned long aligned_addr;
    int start_offset, region_size, region_bits;
    volatile unsigned int alloc_size;

    aligned_addr = tmp_addr & PAGE_MASK;
    start_offset = tmp_addr - aligned_addr;
    region_size = ALIGN_VAL(start_offset + map_size, PAGE_SIZE);

    alloc_size = sizeof(struct fake_chunk) +
                 BITS_TO_LONGS(region_size >> PAGE_SHIFT) * sizeof(unsigned long);
    puts("  alloc1="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    int nr_pages = region_size >> PAGE_SHIFT;
    region_bits = (nr_pages * PAGE_SIZE) / PCPU_MIN_ALLOC_SIZE;

    alloc_size = BITS_TO_LONGS(region_bits) * sizeof(unsigned long);
    puts("  alloc2="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    alloc_size = BITS_TO_LONGS(region_bits + 1) * sizeof(unsigned long);
    puts("  alloc3="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    alloc_size = (region_size / (PAGE_SIZE * 2)) * 24;
    puts("  alloc4="); puthex(alloc_size); puts("\r\n");
    fake_memblock_alloc(alloc_size, SMP_CACHE_BYTES);

    return 0;
}

int main(void)
{
    // Simulate typical pcpu parameters
    unsigned long tmp_addr = 0x83f78000;
    int map_size = 0x8000; // 32KB

    puts("=== Without volatile ===\r\n");
    alloc_counter = 0x80100000;
    test_without_volatile(tmp_addr, map_size);

    puts("\r\n=== With volatile ===\r\n");
    alloc_counter = 0x80100000;
    test_with_volatile(tmp_addr, map_size);

    puts("\r\nDone\r\n");
    return 0;
}
