// Test: pointer arithmetic
// Expected: arr[2] = 30 (0x1E)
int arr[4] = {10, 20, 30, 40};

int main(void) {
    int *p = arr;
    p = p + 2;  // Point to arr[2]
    return *p;
}
