// Test: void function with side effect
// Expected: 50 (0x32)
int result;

void set_result(int x) {
    result = x;
}

int main(void) {
    set_result(50);
    return result;
}
