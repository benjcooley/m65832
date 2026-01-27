// Test: FP multiplication
// Expected: 12 (int cast of 3.0 * 4.0 = 12.0)

int main(void) {
    volatile float x = 3.0f;
    volatile float y = 4.0f;
    float prod = x * y;  // 12.0
    return (int)prod;  // 12
}
