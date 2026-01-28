// Test: ctype toupper()
// Expected: toupper('a') = 'A' = 65

int toupper(int c) {
    if (c >= 'a' && c <= 'z') return c - 32;
    return c;
}

int main(void) {
    return toupper('a');
}
