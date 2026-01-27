// Test: nested for loops
// Expected: 3 * 4 = 12 iterations
int main(void) {
    int count = 0;
    for (int i = 0; i < 3; i = i + 1) {
        for (int j = 0; j < 4; j = j + 1) {
            count = count + 1;
        }
    }
    return count;
}
