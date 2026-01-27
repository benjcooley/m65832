// Test: early return from function
// Expected: 10 (early return path)
int check(int x) {
    if (x > 5) {
        return 10;
    }
    return 20;
}

int main(void) {
    return check(100);
}
