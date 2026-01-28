// Comprehensive string function tests for picolibc
// Returns: number of failed tests (0 = all pass)

#include <string.h>
#include <stdlib.h>

static int errors = 0;

#define TEST_EQ(val, expected) do { if ((val) != (expected)) errors++; } while(0)
#define TEST_STR(s, expected) do { if (strcmp((s), (expected)) != 0) errors++; } while(0)

// Test strlen
static void test_strlen(void) {
    TEST_EQ(strlen(""), 0);
    TEST_EQ(strlen("a"), 1);
    TEST_EQ(strlen("hello"), 5);
    TEST_EQ(strlen("hello world"), 11);
}

// Test strcpy
static void test_strcpy(void) {
    char buf[32];
    strcpy(buf, "hello");
    TEST_STR(buf, "hello");
    strcpy(buf, "");
    TEST_STR(buf, "");
    strcpy(buf, "test");
    TEST_STR(buf, "test");
}

// Test strcmp
static void test_strcmp(void) {
    TEST_EQ(strcmp("abc", "abc"), 0);
    TEST_EQ(strcmp("abc", "abd") < 0, 1);
    TEST_EQ(strcmp("abd", "abc") > 0, 1);
    TEST_EQ(strcmp("", ""), 0);
    TEST_EQ(strcmp("a", "") > 0, 1);
}

// Test strncmp
static void test_strncmp(void) {
    TEST_EQ(strncmp("abcd", "abce", 3), 0);
    TEST_EQ(strncmp("abcd", "abce", 4) < 0, 1);
    TEST_EQ(strncmp("", "", 5), 0);
}

// Test memset
static void test_memset(void) {
    char buf[16];
    memset(buf, 'x', 8);
    buf[8] = '\0';
    TEST_STR(buf, "xxxxxxxx");
    
    memset(buf, 0, 4);
    TEST_EQ(buf[0], 0);
    TEST_EQ(buf[3], 0);
    TEST_EQ(buf[4], 'x');
}

// Test memcpy
static void test_memcpy(void) {
    char src[] = "hello";
    char dst[16] = {0};
    memcpy(dst, src, 6);
    TEST_STR(dst, "hello");
    
    // Overlapping shouldn't be used with memcpy but test non-overlap
    memcpy(dst + 6, src, 3);
    TEST_EQ(dst[6], 'h');
    TEST_EQ(dst[8], 'l');
}

// Test memmove (handles overlapping)
static void test_memmove(void) {
    char buf[] = "abcdefgh";
    memmove(buf + 2, buf, 4);  // "ababcdgh"
    TEST_EQ(buf[2], 'a');
    TEST_EQ(buf[3], 'b');
    TEST_EQ(buf[4], 'c');
    TEST_EQ(buf[5], 'd');
}

// Test memcmp
static void test_memcmp(void) {
    TEST_EQ(memcmp("abc", "abc", 3), 0);
    TEST_EQ(memcmp("abc", "abd", 3) < 0, 1);
    TEST_EQ(memcmp("abd", "abc", 3) > 0, 1);
}

// Test strchr
static void test_strchr(void) {
    const char *s = "hello";
    TEST_EQ(strchr(s, 'e') - s, 1);
    TEST_EQ(strchr(s, 'l') - s, 2);
    TEST_EQ(strchr(s, 'x'), (char*)0);
    TEST_EQ(strchr(s, '\0') - s, 5);
}

// Test strrchr
static void test_strrchr(void) {
    const char *s = "hello";
    TEST_EQ(strrchr(s, 'l') - s, 3);  // Last 'l'
    TEST_EQ(strrchr(s, 'h') - s, 0);
    TEST_EQ(strrchr(s, 'x'), (char*)0);
}

// Test strstr
static void test_strstr(void) {
    const char *s = "hello world";
    TEST_EQ(strstr(s, "world") - s, 6);
    TEST_EQ(strstr(s, "hello") - s, 0);
    TEST_EQ(strstr(s, "xyz"), (char*)0);
    TEST_EQ(strstr(s, "") - s, 0);  // Empty string matches at start
}

// Test strcat
static void test_strcat(void) {
    char buf[32] = "hello";
    strcat(buf, " world");
    TEST_STR(buf, "hello world");
}

// Test strncat
static void test_strncat(void) {
    char buf[32] = "hello";
    strncat(buf, " world!!!", 6);
    TEST_STR(buf, "hello world");
}

// Test atoi
static void test_atoi(void) {
    TEST_EQ(atoi("123"), 123);
    TEST_EQ(atoi("-456"), -456);
    TEST_EQ(atoi("0"), 0);
    TEST_EQ(atoi("  42"), 42);
}

// Test abs
static void test_abs(void) {
    TEST_EQ(abs(5), 5);
    TEST_EQ(abs(-5), 5);
    TEST_EQ(abs(0), 0);
}

int main(void) {
    test_strlen();
    test_strcpy();
    test_strcmp();
    test_strncmp();
    test_memset();
    test_memcpy();
    test_memmove();
    test_memcmp();
    test_strchr();
    test_strrchr();
    test_strstr();
    test_strcat();
    test_strncat();
    test_atoi();
    test_abs();
    
    return errors;
}
