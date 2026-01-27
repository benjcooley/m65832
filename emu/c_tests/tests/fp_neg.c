// Test: FP negation
// Expected: -7 (0xFFFFFFF9) as int from -7.0

int main(void) {
    volatile float x = 7.0f;
    float neg = -x;  // -7.0
    return (int)neg;  // -7
}
