// Test: write through pointer
// Expected: 100 (0x64)
int main(void) {
    int x = 0;
    int *p = &x;
    *p = 100;
    return x;
}
