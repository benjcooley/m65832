// Test: sizeof struct
// Expected: 8 (two ints)
struct Pair {
    int a;
    int b;
};

int main(void) {
    return sizeof(struct Pair);
}
