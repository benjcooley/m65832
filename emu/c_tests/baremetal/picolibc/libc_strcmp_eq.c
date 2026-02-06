// Test: strcmp equal strings
// Expected: 1
#include <string.h>
char s1[] = "abc";
char s2[] = "abc";
int main(void) {
    if (strcmp(s1, s2) == 0) return 1;
    return 0;
}

