// Test: Array copy element by element
// Expected: 100 (first element)
int src[3] = {100, 200, 300};
int dst[3];

int main(void) {
    dst[0] = src[0];
    dst[1] = src[1];
    dst[2] = src[2];
    return dst[0];
}
