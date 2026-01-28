// Test: strcmp from m65832-stdlib  
// Expected: strcmp equal strings = 0
#include <string.h>

char s1[] = "abc";
char s2[] = "abc";

int main(void) {
    return strcmp(s1, s2);
}
