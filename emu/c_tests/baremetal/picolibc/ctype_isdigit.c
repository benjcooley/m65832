// Test: ctype isdigit()
// Expected: count of digits in "a1b2c3" = 3

int isdigit(int c) {
    return c >= '0' && c <= '9';
}

int main(void) {
    const char *s = "a1b2c3";
    int count = 0;
    while (*s) {
        if (isdigit(*s)) count++;
        s++;
    }
    return count;
}
