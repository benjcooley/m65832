# Algorithm Tests
# Sourced by run_c_tests.sh

# NOTE: Some algorithm tests disabled due to compiler limitations:
# - GCD: complex loop codegen issue
# - Prime: requires mul(reg,reg) which isn't implemented

# run_test "GCD (48, 18)"       "tests/algo_gcd.c"          "00000006"
# run_test "Is prime (17)"      "tests/algo_prime.c"        "00000001"
run_test "Power (2^10)"       "tests/algo_power.c"        "00000400"
run_test "Absolute value"     "tests/algo_abs.c"          "0000002A"
run_test "Minimum"            "tests/algo_min.c"          "00000014"
run_test "Maximum"            "tests/algo_max.c"          "0000001E"
run_test "Sum digits"         "tests/algo_sum_digits.c"   "0000000F"
