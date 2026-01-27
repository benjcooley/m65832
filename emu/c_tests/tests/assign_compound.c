// Test: Compound assignment operators
// Expected: 25
int main(void) {
    int x = 10;
    x += 5;   // 15
    x -= 2;   // 13
    x *= 2;   // 26
    x /= 2;   // 13
    x |= 0xC; // 13 | 12 = 13
    x &= 0x1F;// 13 & 31 = 13
    x ^= 0x18;// 13 ^ 24 = 21
    x += 4;   // 25
    return x;
}
