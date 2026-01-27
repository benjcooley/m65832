// Test: Switch with default
// Expected: 99
int main(void) {
    int x = 10;
    int result;
    switch (x) {
        case 1: result = 10; break;
        case 2: result = 20; break;
        default: result = 99; break;
    }
    return result;
}
