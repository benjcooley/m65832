// Test: Reverse linked list simulation
// Expected: 30 (was last, now first)
int values[3] = {10, 20, 30};

int main(void) {
    // Original order: values[0], values[1], values[2]
    // Reversed order: values[2], values[1], values[0]
    // Return first of reversed = values[2] = 30
    return values[2];
}
