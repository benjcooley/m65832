// Test: continue statement (sum only even numbers)
// Expected: 2+4+6+8+10 = 30 (0x1E)
int main(void) {
    int sum = 0;
    for (int i = 1; i <= 10; i = i + 1) {
        if (i % 2 != 0) {
            continue;
        }
        sum = sum + i;
    }
    return sum;
}
