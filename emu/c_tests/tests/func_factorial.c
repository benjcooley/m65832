// Test: recursive factorial
// Expected: 5! = 120 (0x78)
int factorial(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

int main(void) {
    return factorial(5);
}
