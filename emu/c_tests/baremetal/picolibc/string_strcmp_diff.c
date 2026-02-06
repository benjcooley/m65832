// Test: string strcmp() with different strings
// Expected: 1

int strcmp(const char *s1, const char *s2) {
    while (*s1) {
        if (*s1 != *s2) break;
        s1++;
        s2++;
    }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int main(void) {
    int result = strcmp("abc", "abd");
    if (result < 0) return 1;  // Return 1 if abc < abd
    return 0;
}
