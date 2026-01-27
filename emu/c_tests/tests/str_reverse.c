// Test: Array reverse using explicit swaps
// Expected: 50 (last element becomes first after reverse)
int arr[5] = {10, 20, 30, 40, 50};

int main(void) {
    // Reverse 5 elements: swap 0<->4, 1<->3, 2 stays
    int tmp;
    
    tmp = arr[0];
    arr[0] = arr[4];
    arr[4] = tmp;
    
    tmp = arr[1];
    arr[1] = arr[3];
    arr[3] = tmp;
    
    return arr[0];  // Should be 50
}
