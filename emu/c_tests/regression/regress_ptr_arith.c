// Regression test: stack pointer arithmetic addressing
// Bug: stack-local pointer arithmetic could select an address with @<noreg>
//      when combining FrameIndex with a constant offset.
// Expected: 0x63 ('c')

int main(void) {
    char buf[] = "abcdefgh";
    // Force the address to escape so the load cannot be constant-folded.
    __asm__ volatile("" : : "r"(buf) : "memory");
    return (unsigned char)buf[2];
}
