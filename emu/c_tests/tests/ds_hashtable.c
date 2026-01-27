// Test: Simple hash table (direct mapping, no functions)
// Expected: 42 (value for key 7)
int keys[8];
int values[8];
int used[8];

int main(void) {
    // Initialize
    int i = 0;
    while (i < 8) {
        used[i] = 0;
        i++;
    }
    
    // Put key 5 -> 100 at slot 5
    keys[5] = 5;
    values[5] = 100;
    used[5] = 1;
    
    // Put key 7 -> 42 at slot 7
    keys[7] = 7;
    values[7] = 42;
    used[7] = 1;
    
    // Get key 7
    if (used[7] && keys[7] == 7) {
        return values[7];
    }
    return -1;
}
