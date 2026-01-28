// Regression test: BRCOND instruction selection bug fix
// Bug: Backend couldn't select 'brcond' nodes (branch on boolean condition).
//      Only BR_CC (compare-and-branch) was handled.
// Fix: Added setOperationAction(ISD::BRCOND, MVT::Other, Expand)
//
// This test uses complex boolean expressions that generate BRCOND nodes.
// The key is that the code COMPILES - the original bug crashed the compiler.
// Expected: 42

int test_complex_bool(int a, int b, int c) {
    // Complex boolean - generates 'and' of 'or' of conditions
    // This pattern caused the original crash in print_num()
    if ((a > 0 && b > 0) || (c > 0 && a < 10)) {
        return 42;
    }
    return 0;
}

int test_negated_bool(int x, int y) {
    // Negated boolean expression
    int cond = (x > 5);
    if (!cond && y > 0) {
        return 10;
    }
    return 20;
}

int main(void) {
    // Test 1: Complex boolean with &&/||
    int r1 = test_complex_bool(5, 3, 0);  // a>0 && b>0 is true, returns 42
    if (r1 != 42) return 1;
    
    // Test 2: Negated boolean
    int r2 = test_negated_bool(3, 5);     // x=3 not > 5, so cond=0, !cond=1, y>0, returns 10
    if (r2 != 10) return 2;
    
    // Test 3: Another complex case
    int r3 = test_complex_bool(0, 0, 5);  // a>0 is false, but c>0 && a<10 is true
    if (r3 != 42) return 3;
    
    return 42;  // All tests passed = 0x2A
}
