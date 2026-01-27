// Test: while loop
// Expected: sum of 1+2+3+4+5+6+7+8+9+10 = 55 (0x37)
int main(void) {
    int sum = 0;
    int i = 1;
    while (i <= 10) {
        sum = sum + i;
        i = i + 1;
    }
    return sum;
}
