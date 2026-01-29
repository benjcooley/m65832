# Function Tests - Comprehensive function call/argument patterns
# Sourced by run_c_tests.sh

# Mixed-size function arguments
run_test "Byte arguments"       "tests/func_args_byte.c"       "00000055"
run_test "Half arguments"       "tests/func_args_half.c"       "00003333"
run_test "Mixed arguments"      "tests/func_args_mixed.c"      "00000001"

# Original tests (backward compat)
run_test "Simple call"          "tests/func_simple_call.c"     "0000002A"
run_test "With args"            "tests/func_args.c"            "00000039"
run_test "Local vars"           "tests/func_local_vars.c"      "0000001E"
run_test "Multiple args"        "tests/func_multi_args.c"      "00000024"
run_test "Nested calls"         "tests/func_nested_calls.c"    "00000042"
run_test "Return struct"        "tests/func_return_struct.c"   "00000001"
