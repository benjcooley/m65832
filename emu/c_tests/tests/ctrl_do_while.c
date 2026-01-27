// Test: do-while loop (executes at least once)
// Expected: 5 iterations, result = 5
int main(void) {
    int count = 0;
    do {
        count = count + 1;
    } while (count < 5);
    return count;
}
