// Test: minimum of two values
// Expected: min(30, 20) = 20
int min(int a, int b) {
    if (a < b) {
        return a;
    }
    return b;
}

int main(void) {
    return min(30, 20);
}
