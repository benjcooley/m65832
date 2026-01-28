#!/bin/bash
# Operator tests (increment, decrement, compound assignment)

run_test "Pre-increment"        "tests/incr_pre.c"          "00000006"
run_test "Post-increment"       "tests/incr_post.c"         "00000005"
run_test "Pre-decrement"        "tests/decr_pre.c"          "00000004"
run_test "Post-decrement"       "tests/decr_post.c"         "00000005"
run_test "Compound assign"      "tests/assign_compound.c"   "00000019"
run_test "Double pointer"       "tests/ptr_double.c"        "0000002A"
run_test "2D array"             "tests/array_2d.c"          "00000006"
