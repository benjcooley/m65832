// Test: stdlib atoi() with negative - simple version
// Expected: 50

int atoi_neg(const char *s) {
    int result = 0;
    int neg = 0;
    
    if (*s == '-') {
        neg = 1;
        s++;
    }
    
    while (1) {
        char c = *s;
        if (c < '0') break;
        if (c > '9') break;
        result = result * 10 + (c - '0');
        s++;
    }
    
    if (neg) return -result;
    return result;
}

int main(void) {
    int x = atoi_neg("-50");
    if (x < 0) return -x;
    return x;  // Return 50
}
