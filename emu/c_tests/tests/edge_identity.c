// Test: identity operations
// Expected: 42
int main(void) {
    int x = 42;
    x = x + 0;  // Add zero
    x = x * 1;  // Multiply by one
    x = x / 1;  // Divide by one
    return x;
}
