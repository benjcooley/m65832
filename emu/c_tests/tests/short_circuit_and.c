// Test: Short-circuit AND (second not evaluated if first is false)
// Expected: 10 (side effect not executed)
int side = 10;

int effect(void) {
    side = 99;
    return 1;
}

int main(void) {
    int result = 0 && effect();  // effect() should NOT be called
    return side;  // Should still be 10
}
