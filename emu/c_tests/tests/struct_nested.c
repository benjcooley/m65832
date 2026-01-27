// Test: Nested struct access
// Expected: 15 (5 + 10)
struct Inner {
    int a;
    int b;
};

struct Outer {
    struct Inner in;
    int c;
};

int main(void) {
    struct Outer o;
    o.in.a = 5;
    o.in.b = 10;
    o.c = 100;
    return o.in.a + o.in.b;
}
