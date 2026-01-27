// Test: primality check (using addition instead of multiplication)
// Expected: isPrime(17) = 1
int isPrime(int n) {
    if (n < 2) return 0;
    // Check divisibility by trial subtraction
    for (int i = 2; i < n; i = i + 1) {
        // Check if i divides n by repeated subtraction
        int temp = n;
        while (temp >= i) {
            temp = temp - i;
        }
        if (temp == 0) return 0;  // i divides n
    }
    return 1;
}

int main(void) {
    return isPrime(17);
}
