#!/bin/bash
# Sizeof tests

run_test "sizeof(int)"          "tests/sizeof_int.c"        "00000004"
run_test "sizeof(pointer)"      "tests/sizeof_ptr.c"        "00000004"
run_test "sizeof(struct)"       "tests/sizeof_struct.c"     "00000008"
