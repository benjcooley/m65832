// Test: string strcmp()
// Expected: strcmp("abc", "abc") = 0

int strcmp(const char *s1, const char *s2) {
    while (*s1) {
        if (*s1 != *s2) break;
        s1++;
        s2++;
    }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int main(void) {
    return strcmp("abc", "abc");
}
