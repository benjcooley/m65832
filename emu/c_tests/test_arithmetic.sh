# Arithmetic Tests
# Sourced by run_c_tests.sh

# Basic operations
run_test "Add constants"      "tests/arith_add.c"        "00000030"
run_test "Subtract"           "tests/arith_sub.c"        "00000020"
run_test "Negation"           "tests/arith_neg.c"        "FFFFFFE0"
run_test "Chained arithmetic" "tests/arith_chain.c"      "00000064"

# Multiply/divide/modulo (constants only - compiler limitation for dynamic mul)
run_test "Multiply"           "tests/arith_mul.c"        "0000002A"
run_test "Divide"             "tests/arith_div.c"        "00000019"
run_test "Modulo"             "tests/arith_mod.c"        "00000002"
run_test "Multiply large"     "tests/arith_mul_large.c"  "0000C350"
run_test "Divide truncate"    "tests/arith_div_round.c"  "00000002"
run_test "Negative multiply"  "tests/arith_neg_mul.c"    "FFFFFFF1"
run_test "Compound expr"      "tests/arith_compound.c"   "00000016"
run_test "Precedence"         "tests/arith_precedence.c" "0000000E"

# 64-bit arithmetic
run_test "64-bit basic"       "tests/test_64bit_basic.c"    "00000000" 500000
run_test "64-bit multiply"    "tests/test_64bit_multiply.c" "00000000" 500000
run_test "64-bit divide"      "tests/test_64bit_divide.c"   "00000000" 500000
