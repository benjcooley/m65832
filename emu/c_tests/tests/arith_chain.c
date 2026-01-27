// Test: Chained arithmetic
// Expected: 0x64 ((10 + 20) * 2 + 40 = 100)

int main(void) {
    int a = 10 + 20;    // 30
    int b = a + a;      // 60 (simulating *2)
    int c = b + 40;     // 100
    return c;
}
