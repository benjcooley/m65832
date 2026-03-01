// Regression test: struct field string literal initialization
// Bug: At -Os/-O2, the compiler generates incorrect code for
// struct initialization with .name = "string_literal", producing
// NULL or garbage pointers where the string address should be.
//
// Observed in: struct console in arch/m65832/kernel/setup.c
//   .name = "rawuart" → becomes NULL at runtime
//
// Expected: return 0 (all checks pass)

struct device {
    const char *name;
    void (*write)(const char *s, unsigned n);
    int flags;
    int index;
};

static void dummy_write(const char *s, unsigned n) {
    (void)s; (void)n;
}

static struct device my_dev = {
    .name   = "testdev",
    .write  = dummy_write,
    .flags  = 3,
    .index  = -1,
};

static int streq(const char *a, const char *b) {
    while (*a && *b) {
        if (*a != *b) return 0;
        a++; b++;
    }
    return *a == *b;
}

int main(void) {
    /* Check that .name is not NULL */
    if (my_dev.name == 0)
        return 1;

    /* Check that .name points to the right string */
    if (!streq(my_dev.name, "testdev"))
        return 2;

    /* Check that .write is not NULL */
    if (my_dev.write == 0)
        return 3;

    /* Check that .flags is correct */
    if (my_dev.flags != 3)
        return 4;

    /* Check that .index is correct */
    if (my_dev.index != -1)
        return 5;

    /* Check a local struct too (not just static) */
    struct device local_dev = {
        .name   = "localdev",
        .write  = dummy_write,
        .flags  = 7,
        .index  = 0,
    };

    if (local_dev.name == 0)
        return 6;

    if (!streq(local_dev.name, "localdev"))
        return 7;

    return 0;
}
