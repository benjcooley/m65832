// Test: pointer dereference
// Expected: 42 (0x2A)
int main(void) {
    int x = 42;
    int *p = &x;
    return *p;
}
