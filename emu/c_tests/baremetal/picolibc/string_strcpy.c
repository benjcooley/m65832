// Test: string strcpy()
// Expected: strcpy copies string, return length of result = 5

typedef unsigned int size_t;

// Actual strcpy implementation
char *strcpy(char *dst, const char *src) {
    char *d = dst;
    while ((*d++ = *src++));
    return dst;
}

// Actual strlen implementation  
size_t strlen(const char *s) {
    const char *p = s;
    while (*p) p++;
    return p - s;
}

char src_str[6] = {'h', 'e', 'l', 'l', 'o', 0};
char buffer[32];

int main(void) {
    strcpy(buffer, src_str);
    return strlen(buffer);
}
