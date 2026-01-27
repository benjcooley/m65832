// Test: count set bits (popcount)
// Expected: popcount(0xF0F0) = 8
int main(void) {
    int x = 0xF0F0;
    int count = 0;
    while (x) {
        count = count + (x & 1);
        x = x >> 1;
    }
    return count;
}
