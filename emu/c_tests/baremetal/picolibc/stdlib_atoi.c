// Test: stdlib atoi() - simple version
// Expected: atoi("123") = 123

int atoi_simple(const char *s) {
    int result = 0;
    while (1) {
        char c = *s;
        if (c < '0') break;
        if (c > '9') break;
        result = result * 10 + (c - '0');
        s++;
    }
    return result;
}

int main(void) {
    return atoi_simple("123");
}
