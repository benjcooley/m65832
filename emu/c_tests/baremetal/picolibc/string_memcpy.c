// Test: string memcpy()
// Expected: memcpy copies 4 bytes, sum = 10

typedef unsigned int size_t;

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

int main(void) {
    unsigned char src[4] = {1, 2, 3, 4};
    unsigned char dst[4];
    
    memcpy(dst, src, 4);
    
    return dst[0] + dst[1] + dst[2] + dst[3];  // 1+2+3+4 = 10
}
