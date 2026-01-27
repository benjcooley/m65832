// Test: FP addition
// Expected: 5 (int cast of 2.5 + 2.5 = 5.0)

float fadd(float a, float b) {
    return a + b;
}

int main(void) {
    float x = 2.5f;
    float y = 2.5f;
    float sum = fadd(x, y);  // 5.0
    return (int)sum;  // 5
}
