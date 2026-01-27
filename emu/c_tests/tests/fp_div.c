// Test: FP division
// Expected: 5 (int cast of 20.0 / 4.0 = 5.0)

int main(void) {
    volatile float x = 20.0f;
    volatile float y = 4.0f;
    float quot = x / y;  // 5.0
    return (int)quot;  // 5
}
