// Test: Switch fallthrough
// Expected: 60 (10+20+30)
int main(void) {
    int x = 1;
    int result = 0;
    switch (x) {
        case 1: result += 10;
        case 2: result += 20;
        case 3: result += 30; break;
        default: result = 0; break;
    }
    return result;
}
