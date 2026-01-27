// Test: Array sum with pointer arithmetic
// Expected: 150 (10+20+30+40+50)
int arr[5] = {10, 20, 30, 40, 50};

int main(void) {
    int sum = 0;
    int *p = arr;
    int *end = arr + 5;
    while (p < end) {
        sum += *p;
        p++;
    }
    return sum;
}
