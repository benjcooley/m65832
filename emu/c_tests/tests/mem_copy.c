// Test: Memory copy using array indexing
// Expected: 99 (second element)
int src[3] = {42, 99, 17};
int dst[3];

int main(void) {
    // Copy 3 ints
    dst[0] = src[0];
    dst[1] = src[1];
    dst[2] = src[2];
    return dst[1];
}
