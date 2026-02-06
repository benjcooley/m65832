// Test: ctype isdigit()
// Expected: count of digits in "a1b2c3" = 3

int isdigit(int c) {
    if (c >= '0') {
        if (c <= '9') return 1;
    }
    return 0;
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
