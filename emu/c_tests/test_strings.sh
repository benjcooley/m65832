#!/bin/bash
# Array/memory operation tests (using ints to avoid byte load issues)

run_test "Array length"         "tests/str_length.c"        "00000005"
run_test "Array compare"        "tests/str_compare.c"       "00000000"
run_test "Array copy"           "tests/str_copy.c"          "00000064"
run_test "Array reverse"        "tests/str_reverse.c"       "00000032"
run_test "Memory copy"          "tests/mem_copy.c"          "00000063"
run_test "Memory set"           "tests/mem_set.c"           "00000055"
