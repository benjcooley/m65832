// Test: string memset()
// Expected: 264

typedef unsigned int size_t;

void *memset(void *s, int c, size_t n) {
    unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

int main(void) {
    unsigned char buf[4];
    
    memset(buf, 0x42, 4);
    
    return buf[0] + buf[1] + buf[2] + buf[3];  // 0x42*4 = 264
}
