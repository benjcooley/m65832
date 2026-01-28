// Test: string strcmp() with different strings
// Expected: 1

int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int main(void) {
    int result = strcmp("abc", "abd");
    return result < 0 ? 1 : 0;  // Return 1 if abc < abd
}
