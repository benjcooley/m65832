// Test: power of 2 function (using shifts)
// Expected: 2^10 = 1024 (0x400)
int power2(int exp) {
    return 1 << exp;
}

int main(void) {
    return power2(10);
}
