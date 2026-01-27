// Test: set specific bit
// Expected: 0x01 | 0x10 = 0x11 (17)
int main(void) {
    int x = 1;
    return x | 0x10;
}
