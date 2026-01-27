// Test: write to array then read back
// Expected: 99 (0x63)
int arr[3];

int main(void) {
    arr[0] = 10;
    arr[1] = 99;
    arr[2] = 30;
    return arr[1];
}
