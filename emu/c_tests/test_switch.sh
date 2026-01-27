#!/bin/bash
# Switch statement tests

run_test "Switch basic"         "tests/switch_basic.c"      "00000014"
run_test "Switch default"       "tests/switch_default.c"    "00000063"
run_test "Switch fallthrough"   "tests/switch_fallthrough.c" "0000003C"
