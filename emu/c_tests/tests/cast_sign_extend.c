// Test: Sign extension from char to int
// Expected: -1 (0xFFFFFFFF)
int main(void) {
    signed char c = -1;  // 0xFF
    int i = (int)c;  // Should sign-extend to 0xFFFFFFFF
    return i;
}
