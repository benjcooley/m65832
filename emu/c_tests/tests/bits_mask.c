// Test: bit masking
// Expected: 0xABCD & 0x00FF = 0xCD (205)
int main(void) {
    int x = 0xABCD;
    return x & 0xFF;
}
