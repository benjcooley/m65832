// Test: Find maximum in array
// Expected: 99
int arr[6] = {23, 45, 99, 12, 67, 34};

int main(void) {
    int max = arr[0];
    for (int i = 1; i < 6; i++) {
        if (arr[i] > max) {
            max = arr[i];
        }
    }
    return max;
}
