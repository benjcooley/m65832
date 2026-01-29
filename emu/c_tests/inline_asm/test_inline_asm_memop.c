// Test inline assembly with memory-like operations
// Note: Full "m" constraint support requires backend work
// For now, test patterns that work through registers

int main(void) {
    int failures = 0;
    
    // Test 1: Volatile variable through register
    {
        volatile int src = 42;
        int dst;
        asm volatile(
            "LDA %1\n"
            "STA %0"
            : "=r"(dst)
            : "r"(src)
            : "a"
        );
        if (dst != 42) failures++;
    }
    
    // Test 2: Array access through register
    {
        int arr[4] = {10, 20, 30, 40};
        int idx2 = arr[2];  // Load array element to register
        int val;
        asm volatile(
            "LDA %1\n"
            "STA %0"
            : "=r"(val)
            : "r"(idx2)
            : "a"
        );
        if (val != 30) failures++;
    }
    
    // Test 3: Store to volatile through register
    {
        volatile int dst = 0;
        int val = 99;
        int tmp;
        asm volatile(
            "LDA %1\n"
            "STA %0"
            : "=r"(tmp)
            : "r"(val)
            : "a"
        );
        dst = tmp;
        if (dst != 99) failures++;
    }
    
    // Test 4: Read-modify-write pattern
    {
        int val = 10;
        asm volatile(
            "LDA %0\n"
            "CLC\n"
            "ADC #5\n"
            "STA %0"
            : "+r"(val)
            :
            : "a"
        );
        if (val != 15) failures++;
    }
    
    // Test 5: Multiple volatiles
    {
        volatile int a = 10;
        volatile int b = 20;
        int sum;
        asm volatile(
            "LDA %1\n"
            "CLC\n"
            "ADC %2\n"
            "STA %0"
            : "=r"(sum)
            : "r"(a), "r"(b)
            : "a"
        );
        if (sum != 30) failures++;
    }
    
    // Test 6: Compound volatile operations
    {
        volatile int counter = 5;
        int val = counter;
        asm volatile(
            "LDA %0\n"
            "CLC\n"
            "ADC #1\n"
            "STA %0"
            : "+r"(val)
            :
            : "a"
        );
        counter = val;
        if (counter != 6) failures++;
    }
    
    return failures;
}
