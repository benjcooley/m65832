// Test: sum of digits (hardcoded for 12345)
// Expected: 1+2+3+4+5 = 15
int main(void) {
    // Avoid div/mod with variables - hardcode the digit extraction
    int n = 12345;
    int sum = 0;
    sum = sum + (n / 10000);        // 1
    sum = sum + ((n / 1000) % 10);  // 2
    sum = sum + ((n / 100) % 10);   // 3
    sum = sum + ((n / 10) % 10);    // 4
    sum = sum + (n % 10);           // 5
    return sum;
}
