// Test: Short-circuit OR (second not evaluated if first is true)
// Expected: 10 (side effect not executed)
int side = 10;

int effect(void) {
    side = 99;
    return 0;
}

int main(void) {
    int result = 1 || effect();  // effect() should NOT be called
    return side;  // Should still be 10
}
