// Test: isdigit from m65832-stdlib
// Expected: isdigit('5') returns non-zero, return 1
#include <ctype.h>

int main(void) {
    return isdigit('5') ? 1 : 0;
}
