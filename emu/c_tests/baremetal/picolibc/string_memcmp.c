// Test: string memcmp()
// Expected: memcmp of equal arrays = 0

typedef unsigned int size_t;

int memcmp(const void *s1, const void *s2, size_t n) {
    const unsigned char *p1 = s1;
    const unsigned char *p2 = s2;
    while (n--) {
        if (*p1 != *p2) return *p1 - *p2;
        p1++;
        p2++;
    }
    return 0;
}

int main(void) {
    unsigned char a[4] = {1, 2, 3, 4};
    unsigned char b[4] = {1, 2, 3, 4};
    
    return memcmp(a, b, 4);
}
