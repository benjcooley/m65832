// Test: stdlib abs()
// Expected: abs(-42) = 42

int abs(int j) {
    return j < 0 ? -j : j;
}

int main(void) {
    return abs(-42);
}
