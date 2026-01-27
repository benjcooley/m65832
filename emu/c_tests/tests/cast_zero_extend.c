// Test: Zero extension from unsigned char to int
// Expected: 255 (0x000000FF)
int main(void) {
    unsigned char c = 255;  // 0xFF
    int i = (int)c;  // Should zero-extend to 0x000000FF
    return i;
}
