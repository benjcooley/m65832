// Test: chain of function calls
// Expected: add10(add5(15)) = 30 (0x1E)
int add5(int x) {
    return x + 5;
}

int add10(int x) {
    return x + 10;
}

int main(void) {
    return add10(add5(15));
}
