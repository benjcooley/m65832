// Test: ctype tolower()
// Expected: tolower('Z') = 'z' = 122

int tolower(int c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    return c;
}

int main(void) {
    return tolower('Z');
}
