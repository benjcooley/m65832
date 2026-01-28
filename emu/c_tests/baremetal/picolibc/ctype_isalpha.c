// Test: ctype isalpha()
// Expected: count of letters in "a1b2c3" = 3

int isalpha(int c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
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
