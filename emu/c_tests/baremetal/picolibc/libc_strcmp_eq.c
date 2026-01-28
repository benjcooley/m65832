
#include <string.h>
char s1[] = "abc";
char s2[] = "abc";
int main(void) {
    return strcmp(s1, s2) == 0 ? 1 : 0;
}

