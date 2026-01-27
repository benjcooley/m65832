// Test: operations with zero
// Expected: 0
int main(void) {
    int a = 100;
    return a - a;  // Avoid multiply-by-zero which requires mul(reg,reg)
}
