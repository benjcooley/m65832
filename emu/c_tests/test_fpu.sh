#!/bin/bash
# FPU tests
# Note: run_test function is provided by run_c_tests.sh

run_test "FP add"               "tests/fp_add.c"            "00000005"
run_test "FP compare (5>3)"     "tests/fp_compare.c"        "00000001"
run_test "FP compare (3>5)"     "tests/fp_compare2.c"       "00000000"
run_test "FP runtime add"       "tests/fp_runtime.c"        "0000000A"
run_test "FP subtract"          "tests/fp_sub.c"            "00000003"
run_test "FP multiply"          "tests/fp_mul.c"            "0000000C"
run_test "FP divide"            "tests/fp_div.c"            "00000005"
run_test "FP negate"            "tests/fp_neg.c"            "FFFFFFF9"
run_test "FP int to float"      "tests/fp_int2float.c"      "0000002A"
