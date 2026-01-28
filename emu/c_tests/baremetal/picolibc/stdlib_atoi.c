// Test: stdlib atoi() - simple version
// Expected: atoi("123") = 123

int atoi_simple(const char *s) {
    int result = 0;
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }
    return result;
}

int main(void) {
    return atoi_simple("123");
}
