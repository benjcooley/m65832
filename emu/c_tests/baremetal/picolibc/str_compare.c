// Test: Array compare element by element
// Expected: 0 (arrays are equal)
int a1[3] = {10, 20, 30};
int a2[3] = {10, 20, 30};

int main(void) {
    if (a1[0] != a2[0]) return a1[0] - a2[0];
    if (a1[1] != a2[1]) return a1[1] - a2[1];
    if (a1[2] != a2[2]) return a1[2] - a2[2];
    return 0;
}
