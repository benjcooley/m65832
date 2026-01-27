// Test: recursive fibonacci
// Expected: fib(10) = 55 (0x37)
int fib(int n) {
    if (n <= 1) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    return fib(10);
}
