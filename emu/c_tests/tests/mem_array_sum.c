// Test: array sum
// Expected: 1+2+3+4+5 = 15 (0x0F)
int arr[5] = {1, 2, 3, 4, 5};

int main(void) {
    int sum = 0;
    for (int i = 0; i < 5; i = i + 1) {
        sum = sum + arr[i];
    }
    return sum;
}
