// Test: absolute value
// Expected: abs(-42) = 42
int abs_val(int x) {
    if (x < 0) {
        return -x;
    }
    return x;
}

int main(void) {
    return abs_val(-42);
}
