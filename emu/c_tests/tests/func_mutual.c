// Test: mutually recursive functions
// Expected: isEven(10) = 1
int isOdd(int n);

int isEven(int n) {
    if (n == 0) return 1;
    return isOdd(n - 1);
}

int isOdd(int n) {
    if (n == 0) return 0;
    return isEven(n - 1);
}

int main(void) {
    return isEven(10);
}
