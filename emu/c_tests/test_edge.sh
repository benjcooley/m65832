# Edge Case Tests
# Sourced by run_c_tests.sh

run_test "Multiply by zero"   "tests/edge_zero.c"         "00000000"
run_test "Identity ops"       "tests/edge_identity.c"     "0000002A"
run_test "Max signed int"     "tests/edge_max_int.c"      "7FFFFFFF"
run_test "Min signed int"     "tests/edge_min_int.c"      "80000000"
run_test "Negative one"       "tests/edge_neg_one.c"      "FFFFFFFF"
