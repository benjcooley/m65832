// Test: Binary search (manual 3 iterations for small array)
// Expected: 4 (index of 50)
int arr[8] = {10, 20, 30, 40, 50, 60, 70, 80};

int main(void) {
    int target = 50;
    
    // Iteration 1: mid = 3, arr[3]=40 < 50, go right
    int mid = 3;
    if (arr[mid] == target) return mid;
    
    // Iteration 2: mid = 5, arr[5]=60 > 50, go left
    mid = 5;
    if (arr[mid] == target) return mid;
    
    // Iteration 3: mid = 4, arr[4]=50 == 50, found!
    mid = 4;
    if (arr[mid] == target) return mid;
    
    return -1;
}
