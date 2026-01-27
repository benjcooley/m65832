// Test: nested if statements
// Expected: 30 (outer true, inner true path)
int main(void) {
    int x = 10;
    int result = 0;
    if (x > 5) {
        if (x > 8) {
            result = 30;
        } else {
            result = 20;
        }
    } else {
        result = 10;
    }
    return result;
}
