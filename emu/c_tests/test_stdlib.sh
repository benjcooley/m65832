#!/bin/bash
# C Standard Library Tests

run_test() {
    ./run_c_test.sh "tests/$1" "$2" "${3:-2000}"
}

echo "=== stdlib tests ==="
run_test "stdlib_abs.c" "0000002A"        # abs(-42) = 42 = 0x2A
run_test "stdlib_atoi.c" "0000007B"       # atoi("123") = 123 = 0x7B
run_test "stdlib_atoi_neg.c" "00000032"   # abs(atoi("-50")) = 50 = 0x32

echo ""
echo "=== string tests ==="
run_test "string_strlen.c" "00000005"     # strlen("hello") = 5
run_test "string_strcmp.c" "00000000"     # strcmp("abc","abc") = 0
run_test "string_strcmp_diff.c" "00000001" # strcmp("abc","abd")<0 returns 1
run_test "string_strcpy.c" "00000005"     # strlen after strcpy = 5
run_test "string_memcpy.c" "0000000A"     # 1+2+3+4 = 10 = 0xA
run_test "string_memset.c" "00000108"     # 0x42*4 = 264 = 0x108
run_test "string_memcmp.c" "00000000"     # memcmp equal arrays = 0

echo ""
echo "=== ctype tests ==="
run_test "ctype_isdigit.c" "00000003"     # 3 digits in "a1b2c3"
run_test "ctype_isalpha.c" "00000003"     # 3 letters in "a1b2c3"
run_test "ctype_toupper.c" "00000041"     # toupper('a') = 'A' = 65 = 0x41
run_test "ctype_tolower.c" "0000007A"     # tolower('Z') = 'z' = 122 = 0x7A
