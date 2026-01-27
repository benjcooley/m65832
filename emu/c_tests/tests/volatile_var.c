// Test: Volatile variable (ensure not optimized away)
// Expected: 10
int main(void) {
    volatile int x = 5;
    x = x + 5;
    return x;
}
