// Test: Struct pointer access
// Expected: 42
struct Data {
    int value;
};

int main(void) {
    struct Data d;
    struct Data *p = &d;
    p->value = 42;
    return d.value;
}
