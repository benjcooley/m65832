// Regression test for branch offset bug (2026-01-27)
// Bug: Branch instructions using addImm(N) for "*+N" style offsets weren't
// adjusted for the M65832's PC-relative calculation. The CPU computes
// target = PC + offset, where PC is AFTER the instruction, but addImm(N)
// meant N bytes from instruction START. This caused branches to overshoot
// their targets by 3 bytes (the branch instruction size).
//
// The issue manifested in SELECT_CC expansion where conditional moves
// used BEQ *+8 to skip a 5-byte MOVR_DP instruction, but the actual
// encoded offset was 8 instead of 5, causing execution to jump into
// garbage code.
//
// This test uses conditional expressions which trigger SELECT_CC lowering.

int select_val(int cond, int a, int b) {
    return cond ? a : b;
}

int main(void) {
    int result = 0;
    
    // Test basic conditional selection
    result += select_val(1, 10, 20);  // Should be 10
    result += select_val(0, 10, 20);  // Should be 20
    
    // Test with computed conditions
    int x = 5;
    result += select_val(x > 3, 100, 200);   // Should be 100
    result += select_val(x < 3, 100, 200);   // Should be 200
    
    // Test chained selections
    int y = select_val(x == 5, 1, 0);
    result += y * 1000;  // Should be 1000
    
    // Expected: 10 + 20 + 100 + 200 + 1000 = 1330 = 0x532
    return result;
}
