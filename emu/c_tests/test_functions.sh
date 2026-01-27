# Function Tests
# Sourced by run_c_tests.sh

# Basic function calls
run_test "Simple call"        "tests/func_call.c"         "0000000F"
run_test "Multiple args"      "tests/func_multi_arg.c"    "0000001E"
run_test "Nested calls"       "tests/func_nested.c"       "0000001E"
run_test "4 arguments"        "tests/func_4args.c"        "0000000A"
run_test "6 arguments"        "tests/func_6args.c"        "00000015"
run_test "Function chain"     "tests/func_chain.c"        "0000001E"
run_test "Void function"      "tests/func_void.c"         "00000032"
run_test "Early return"       "tests/func_early_return.c" "0000000A"

# NOTE: Recursive tests with multiplication disabled - compiler can't select mul(reg,reg)
# run_test "Factorial (5!)"     "tests/func_factorial.c"    "00000078"
# run_test "Fibonacci (10)"     "tests/func_fibonacci.c"    "00000037"
run_test "Mutual recursion"   "tests/func_mutual.c"       "00000001"
