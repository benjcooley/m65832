// Test: Memory set using array indexing
// Expected: 0x55 (85)
char buf[8];

int main(void) {
    int i = 0;
    while (i < 8) {
        buf[i] = 0x55;
        i++;
    }
    return buf[4] & 0xFF;
}
