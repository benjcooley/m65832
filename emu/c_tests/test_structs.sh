#!/bin/bash
# Struct/Union/Enum tests

run_test "Struct basic"         "tests/struct_basic.c"      "0000001E"
run_test "Struct nested"        "tests/struct_nested.c"     "0000000F"
run_test "Struct pointer"       "tests/struct_ptr.c"        "0000002A"
run_test "Union basic"          "tests/union_basic.c"       "00000078"
run_test "Enum basic"           "tests/enum_basic.c"        "00000002"
