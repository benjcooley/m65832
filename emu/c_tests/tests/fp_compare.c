// Test FP comparison
volatile float a = 5.0f;
volatile float b = 3.0f;

int main(void) {
    if (a > b) {
        return 1;  // Should return this (5 > 3)
    }
    return 0;
}
