# Control Flow Tests
# Sourced by run_c_tests.sh

# Basic conditionals
run_test "If-else (true)"     "tests/ctrl_if_true.c"      "0000000A"
run_test "If-else (false)"    "tests/ctrl_if_false.c"     "00000014"
run_test "Nested if"          "tests/ctrl_nested_if.c"    "0000001E"
run_test "Ternary"            "tests/ctrl_ternary.c"      "00000064"

# Loops
run_test "For loop sum"       "tests/ctrl_loop.c"         "0000000F"
run_test "While loop"         "tests/ctrl_while.c"        "00000037"
run_test "Do-while"           "tests/ctrl_do_while.c"     "00000005"
run_test "Nested loops"       "tests/ctrl_nested_loop.c"  "0000000C"
run_test "Break"              "tests/ctrl_break.c"        "00000005"
run_test "Continue"           "tests/ctrl_continue.c"     "0000001E"

# Comparisons
run_test "Compare equal"      "tests/ctrl_cmp_eq.c"       "00000001"
run_test "Compare not-equal"  "tests/ctrl_cmp_ne.c"       "00000001"
run_test "Compare less-than"  "tests/ctrl_cmp_lt.c"       "00000001"
run_test "Compare greater"    "tests/ctrl_cmp_gt.c"       "00000001"
run_test "Compare less-eq"    "tests/ctrl_cmp_le.c"       "00000001"
run_test "Compare greater-eq" "tests/ctrl_cmp_ge.c"       "00000001"

# Logical operators
run_test "Logical AND"        "tests/ctrl_logical_and.c"  "00000001"
run_test "Logical OR"         "tests/ctrl_logical_or.c"   "00000001"
run_test "Logical NOT"        "tests/ctrl_logical_not.c"  "00000001"
