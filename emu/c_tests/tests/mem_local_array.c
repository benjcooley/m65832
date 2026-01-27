// Test: local array on stack
// Expected: 6 (sum of 1+2+3)
int main(void) {
    int arr[3];
    arr[0] = 1;
    arr[1] = 2;
    arr[2] = 3;
    return arr[0] + arr[1] + arr[2];
}
