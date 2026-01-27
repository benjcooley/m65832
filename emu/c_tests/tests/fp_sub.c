// Test: FP subtraction
// Expected: 3 (int cast of 7.5 - 4.5 = 3.0)

int main(void) {
    volatile float x = 7.5f;
    volatile float y = 4.5f;
    float diff = x - y;  // 3.0
    return (int)diff;  // 3
}
