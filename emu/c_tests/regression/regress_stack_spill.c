// Regression test: Stack spill bug fix
// Bug: storeRegToStackSlot/loadRegFromStackSlot used LDA_DP/STA_DP
//      which lacked mayLoad/mayStore flags and didn't support frame indices.
// Fix: Changed to use LOAD32/STORE32 pseudo instructions.
//
// This test forces register spilling by using many local variables.
// Expected: 136 (sum of 1+2+3+...+16 = 136)

int main(void) {
    // Use enough variables to force spilling (M65832 has limited GPRs)
    int a = 1, b = 2, c = 3, d = 4;
    int e = 5, f = 6, g = 7, h = 8;
    int i = 9, j = 10, k = 11, l = 12;
    int m = 13, n = 14, o = 15, p = 16;
    
    // Use all variables to prevent optimization
    int sum = a + b + c + d + e + f + g + h;
    sum += i + j + k + l + m + n + o + p;
    
    return sum;  // Expected: 136 = 0x88
}
