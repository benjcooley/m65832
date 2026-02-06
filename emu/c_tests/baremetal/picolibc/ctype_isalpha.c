// Test: ctype isalpha()
// Expected: count of letters in "a1b2c3" = 3

int isalpha(int c) {
    if (c >= 'A') {
        if (c <= 'Z') return 1;
    }
    if (c >= 'a') {
        if (c <= 'z') return 1;
    }
    return 0;
}

int main(void) {
    const char *s = "a1b2c3";
    int count = 0;
    while (*s) {
        if (isalpha(*s)) count++;
        s++;
    }
    return count;
}
