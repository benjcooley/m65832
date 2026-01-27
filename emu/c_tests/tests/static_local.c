// Test: Global variable increment (simpler version)
// Expected: 3 (incremented 3 times)
int count = 0;

int main(void) {
    count = count + 1;  // 1
    count = count + 1;  // 2
    count = count + 1;  // 3
    return count;
}
