// Test: stdlib atoi() with negative - simple version
// Expected: 50

int atoi_neg(const char *s) {
    int result = 0;
    int neg = 0;
    
    if (*s == '-') {
        neg = 1;
        s++;
    }
    
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }
    
    return neg ? -result : result;
}

int main(void) {
    int x = atoi_neg("-50");
    return x < 0 ? -x : x;  // Return 50
}
