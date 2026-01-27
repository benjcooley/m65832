// Test: Basic enum
// Expected: 2 (GREEN)
enum Color { RED, GREEN, BLUE };

int main(void) {
    enum Color c = GREEN;
    return c + 1;  // 1 + 1 = 2
}
