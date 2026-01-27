// Test: unsigned comparison
// Expected: 1 (0xFFFFFFFF > 0 as unsigned)
int main(void) {
    unsigned int a = 0xFFFFFFFF;
    unsigned int b = 0;
    return a > b;
}
