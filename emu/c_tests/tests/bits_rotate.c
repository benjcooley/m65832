// Test: rotate left using shifts and or
// Expected: rotate 0x12345678 left by 8 = 0x34567812
int main(void) {
    unsigned int x = 0x12345678;
    unsigned int rotated = (x << 8) | (x >> 24);
    return rotated;
}
