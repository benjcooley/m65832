// Test: Euclidean GCD algorithm (using subtraction method)
// Expected: gcd(48, 18) = 6
int gcd(int a, int b) {
    while (a != b) {
        if (a > b) {
            a = a - b;
        } else {
            b = b - a;
        }
    }
    return a;
}

int main(void) {
    return gcd(48, 18);
}
