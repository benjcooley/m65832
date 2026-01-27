// Test: Bubble sort, return first element after sort
// Expected: 12 (smallest value)
int arr[5] = {45, 23, 67, 12, 89};

int main(void) {
    int i = 0;
    while (i < 4) {
        int j = 0;
        while (j < 4 - i) {
            if (arr[j] > arr[j + 1]) {
                int temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
            j++;
        }
        i++;
    }
    return arr[0];  // Should be 12 after sorting
}
