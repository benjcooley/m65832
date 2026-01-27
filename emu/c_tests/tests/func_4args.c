// Test: function with 4 arguments
// Expected: 1+2+3+4 = 10 (0x0A)
int sum4(int a, int b, int c, int d) {
    return a + b + c + d;
}

int main(void) {
    return sum4(1, 2, 3, 4);
}
