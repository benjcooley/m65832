// Test: maximum of two values
// Expected: max(30, 20) = 30
int max(int a, int b) {
    if (a > b) {
        return a;
    }
    return b;
}

int main(void) {
    return max(30, 20);
}
