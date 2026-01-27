// Test: extract bit field
// Expected: extract bits 8-15 from 0xABCDEF12 = 0xEF (239)
int main(void) {
    unsigned int x = 0xABCDEF12;
    return (x >> 8) & 0xFF;
}
