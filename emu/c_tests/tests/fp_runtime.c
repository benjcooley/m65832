// Test: FP operations at runtime (not constant-folded)
// Expected: 10 (result of 3.0 + 7.0)

volatile float global_x = 3.0f;
volatile float global_y = 7.0f;

int main(void) {
    float x = global_x;  // 3.0
    float y = global_y;  // 7.0
    float sum = x + y;   // 10.0
    return (int)sum;     // 10
}
