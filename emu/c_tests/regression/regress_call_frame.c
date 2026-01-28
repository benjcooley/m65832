// Regression test for call frame stack corruption bug (2026-01-27)
// Bug: JSR pushed return address over local variables because call frame
// wasn't properly reserved in the stack allocation.
//
// The issue: when a function has local variables on the stack and calls
// another function, the JSR pushes the return address at SP. If the stack
// frame didn't reserve space for this, the return address overwrites
// the local variables.
//
// This test creates a local buffer and passes it to a callee function.
// If the bug exists, the callee's JSR will corrupt the buffer.

// Simple leaf function that writes to a buffer
void fill_buffer(char *buf, int val, int count) {
    for (int i = 0; i < count; i++) {
        buf[i] = (char)(val + i);
    }
}

int main(void) {
    // Local buffer on stack
    char buf[8];
    
    // Fill buffer via function call
    // If call frame is wrong, JSR will corrupt buf[0:1]
    fill_buffer(buf, 10, 8);
    
    // Verify buffer contents
    int sum = 0;
    for (int i = 0; i < 8; i++) {
        sum += buf[i];
    }
    
    // Expected: 10+11+12+13+14+15+16+17 = 108 = 0x6C
    return sum;
}
