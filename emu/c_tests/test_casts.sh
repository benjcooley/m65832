#!/bin/bash
# Type cast tests

run_test "Char to int"          "tests/cast_char_int.c"     "00000041"
run_test "Int to char"          "tests/cast_int_char.c"     "00000078"
run_test "Sign extend"          "tests/cast_sign_extend.c"  "FFFFFFFF"
run_test "Zero extend"          "tests/cast_zero_extend.c"  "000000FF"
