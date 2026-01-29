// Test inline assembly for atomic operations
// Tests fence instructions and patterns used for atomics

int main(void) {
    int failures = 0;
    
    // Test 1: Memory fence
    {
        volatile int a = 1;
        volatile int b = 2;
        
        a = 10;
        asm volatile("fence" : : : "memory");
        b = a + 10;
        
        if (b != 20) failures++;
    }
    
    // Test 2: Read fence
    {
        volatile int shared = 42;
        int val;
        
        asm volatile("fencer" : : : "memory");
        val = shared;
        
        if (val != 42) failures++;
    }
    
    // Test 3: Write fence  
    {
        volatile int shared = 0;
        
        shared = 77;
        asm volatile("fencew" : : : "memory");
        
        if (shared != 77) failures++;
    }
    
    // Test 4: Compiler barrier (empty asm with memory clobber)
    {
        volatile int x = 1;
        volatile int y = 2;
        
        x = 100;
        asm volatile("" : : : "memory");  // Compiler barrier only
        y = 200;
        
        if (x != 100 || y != 200) failures++;
    }
    
    // Test 5: Atomic-style pattern (simulated with fences)
    // This tests the pattern that would be used with lli/sci
    {
        volatile int counter = 5;
        int oldval, newval;
        
        // Read-modify-write pattern with fences
        asm volatile("fence" : : : "memory");
        oldval = counter;
        newval = oldval + 1;
        counter = newval;
        asm volatile("fence" : : : "memory");
        
        if (counter != 6) failures++;
    }
    
    // Test 6: Multiple barriers
    {
        volatile int a = 10;
        volatile int b = 20;
        int sum;
        
        asm volatile("fence" : : : "memory");
        sum = a + b;
        asm volatile("fence" : : : "memory");
        
        if (sum != 30) failures++;
    }
    
    return failures;
}
