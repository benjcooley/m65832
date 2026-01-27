// Test: Basic union access
// Expected: 0x12 (low byte of 0x12345678)
union Data {
    int i;
    char c;
};

int main(void) {
    union Data d;
    d.i = 0x12345678;
    return d.c & 0xFF;  // Little-endian: low byte is 0x78
}
