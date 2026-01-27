// Test FP comparison - should return 0 (3 is NOT > 5)
volatile float a = 3.0f;
volatile float b = 5.0f;

int main(void) {
    if (a > b) {
        return 1;
    }
    return 0;  // Should return this
}
