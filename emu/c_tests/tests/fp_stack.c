// Test: FP operations with stack-based local variables
// Expected: 15 (5.0 + 10.0 = 15.0 -> 15)
// This tests the compiler's ability to handle stack-relative FP loads

int main(void) {
    float a = 5.0f;   // Local on stack
    float b = 10.0f;  // Local on stack
    float sum = a + b;
    return (int)sum;  // 15
}
