// Test: break statement
// Expected: loop breaks at i=5, returns 5
int main(void) {
    int i;
    for (i = 0; i < 100; i = i + 1) {
        if (i == 5) {
            break;
        }
    }
    return i;
}
