// Test: Nested function calls
// Expected: 0x1E (30)
// double(5) = 10, inner_call(5) = 10+5 = 15, double(15) = 30

int double_val(int x) {
    return x + x;
}

int inner_call(int x) {
    int d = double_val(x);
    return d + 5;
}

int main(void) {
    int a = inner_call(5);  // double(5)+5 = 15
    return double_val(a);   // double(15) = 30
}
