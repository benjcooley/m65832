#!/bin/bash
# Advanced C features tests

run_test "Short-circuit AND"    "tests/short_circuit_and.c" "0000000A"
run_test "Short-circuit OR"     "tests/short_circuit_or.c"  "0000000A"
run_test "Static local"         "tests/static_local.c"      "00000003"
run_test "Static global"        "tests/static_global.c"     "0000002A"
run_test "Const variable"       "tests/const_var.c"         "00000064"
run_test "Volatile variable"    "tests/volatile_var.c"      "0000000A"
