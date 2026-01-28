// Test: strlen from m65832-stdlib
// Expected: strlen("hello") = 5
#include <string.h>

char str[] = "hello";

int main(void) {
    return (int)strlen(str);
}
