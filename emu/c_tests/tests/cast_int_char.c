// Test: Int to char truncation
// Expected: 0x78 (120, low byte of 0x12345678)
int main(void) {
    int i = 0x12345678;
    char c = (char)i;
    return c & 0xFF;
}
