// Test: Find element - simple lookup
// Expected: 3 (index of 40 in {10,20,30,40,50})
int arr[5] = {10, 20, 30, 40, 50};

int main(void) {
    // arr[3] == 40, so return 3
    if (arr[3] == 40) {
        return 3;
    }
    return -1;
}
