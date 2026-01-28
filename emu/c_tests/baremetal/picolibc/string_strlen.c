// Test: string strlen()
// Expected: strlen("hello") = 5

typedef unsigned int size_t;

size_t strlen(const char *s) {
    const char *p = s;
    while (*p) p++;
    return p - s;
}

int main(void) {
    return strlen("hello");
}
