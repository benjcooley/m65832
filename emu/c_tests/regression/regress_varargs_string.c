// Regression test: va_args with %s string pointer
// Bug: When printk/vsnprintf processes a %s format specifier,
// the string pointer fetched from va_list is garbage instead
// of the correct pointer value.
//
// This mimics the kernel's printk("%s", console_name) pattern.
// Expected: return 0 (string matches)

#include <stdarg.h>

static int streq(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *b) {
        if (*a != *b) return 0;
        a++; b++;
    }
    return *a == *b;
}

/* Simplified vsnprintf that just extracts the first %s arg */
static __attribute__((noinline))
const char *extract_string_arg(const char *fmt, ...) {
    va_list ap;
    const char *result = (void *)0;
    
    va_start(ap, fmt);
    
    /* Walk format string looking for %s */
    while (*fmt) {
        if (*fmt == '%' && *(fmt+1) == 's') {
            result = va_arg(ap, const char *);
            break;
        }
        fmt++;
    }
    
    va_end(ap);
    return result;
}

/* Test with multiple arguments before the string */
static __attribute__((noinline))
const char *extract_after_ints(const char *fmt, ...) {
    va_list ap;
    const char *result = (void *)0;
    
    va_start(ap, fmt);
    
    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            if (*fmt == 'd') {
                (void)va_arg(ap, int);
            } else if (*fmt == 's') {
                result = va_arg(ap, const char *);
                break;
            }
        }
        fmt++;
    }
    
    va_end(ap);
    return result;
}

static const char test_str[] = "hello_world";
static const char test_str2[] = "console_name";

int main(void) {
    const char *s;
    
    /* Test 1: Simple %s extraction */
    s = extract_string_arg("name: %s", test_str);
    if (!s)
        return 1;  /* NULL pointer */
    if (!streq(s, "hello_world"))
        return 2;  /* Wrong string */
    
    /* Test 2: %s after %d */
    s = extract_after_ints("val=%d name=%s", 42, test_str2);
    if (!s)
        return 3;
    if (!streq(s, "console_name"))
        return 4;
    
    /* Test 3: %s after multiple %d */
    s = extract_after_ints("a=%d b=%d c=%d name=%s", 1, 2, 3, test_str);
    if (!s)
        return 5;
    if (!streq(s, "hello_world"))
        return 6;
    
    /* Test 4: multiple strings (check second one) */
    s = extract_after_ints("x=%d first=%s", 99, "inline_str");
    if (!s)
        return 7;
    if (!streq(s, "inline_str"))
        return 8;
    
    return 0;
}
