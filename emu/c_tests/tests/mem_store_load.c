// Test: Store then load
// Expected: 0x63 (99)

int test_store_var = 0;

int main(void) {
    test_store_var = 99;
    return test_store_var;
}
