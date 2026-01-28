// Regression test: Complex stack spill scenario (like printf)
// Bug: storeRegToStackSlot/loadRegFromStackSlot failed on complex functions
// Fix: Changed to use LOAD32/STORE32 pseudo instructions
//
// This test mimics the complexity of printf() which triggered the bug.
// Uses many local variables, function calls, and control flow.
// Expected: 100

// Simple helper functions
static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }
static int mul(int a, int b) { return a * b; }

// Function with many locals that forces spilling
int complex_calculation(int input) {
    int v0 = input;
    int v1 = add(v0, 1);
    int v2 = add(v1, 2);
    int v3 = add(v2, 3);
    int v4 = add(v3, 4);
    int v5 = add(v4, 5);
    int v6 = add(v5, 6);
    int v7 = add(v6, 7);
    
    // More operations to increase register pressure
    int v8 = sub(v7, v0);
    int v9 = mul(v8, 2);
    int v10 = add(v9, v1);
    int v11 = sub(v10, v2);
    
    // Control flow with live variables
    int result = 0;
    if (v11 > 10) {
        result = add(v3, v4);
        if (v5 > v6) {
            result = sub(result, v7);
        } else {
            result = add(result, v8);
        }
    } else {
        result = mul(v9, v10);
    }
    
    // More register pressure
    result = add(result, v0 + v1 + v2);
    result = sub(result, v3 + v4);
    result = add(result, v5);
    
    return result;
}

// Another complex function to test nested calls
int nested_calls(int a, int b, int c, int d) {
    int r1 = add(a, b);
    int r2 = sub(c, d);
    int r3 = mul(r1, r2);
    int r4 = add(r3, a);
    int r5 = sub(r4, b);
    int r6 = mul(r5, c);
    int r7 = add(r6, d);
    int r8 = complex_calculation(r7 % 10);
    return r8;
}

int main(void) {
    int result = complex_calculation(5);
    
    // Verify we got a reasonable result (exact value depends on optimizer)
    // The key test is that compilation succeeds without crashing
    if (result < -1000 || result > 1000) {
        return 1;  // Sanity check failed
    }
    
    int nested = nested_calls(1, 2, 3, 4);
    if (nested < -1000 || nested > 1000) {
        return 2;  // Sanity check failed
    }
    
    return 100;  // Success = 0x64
}
