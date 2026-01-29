# Memory Operation Tests - Comprehensive byte/halfword/word memory access
# Sourced by run_c_tests.sh

# Byte array operations
run_test "Byte array access"    "tests/mem_byte_array.c"       "00000001"
run_test "Byte stack vars"      "tests/mem_byte_stack.c"       "00000001"
run_test "Byte loop fill"       "tests/mem_byte_loop.c"        "00000001"

# Halfword array operations
run_test "Half array access"    "tests/mem_half_array.c"       "00000001"
run_test "Half stack vars"      "tests/mem_half_stack.c"       "00000001"

# Original tests (backward compat)
run_test "Load global"          "tests/mem_global.c"           "0000002A"
run_test "Store and load"       "tests/mem_store_load.c"       "00000063"
run_test "Local variable"       "tests/mem_local.c"            "0000007B"
run_test "Multiple locals"      "tests/mem_multi_local.c"      "00000064"

# Arrays
run_test "Array sum"            "tests/mem_array_sum.c"        "0000000F"
run_test "Array index"          "tests/mem_array_index.c"      "00000028"
run_test "Array write"          "tests/mem_array_write.c"      "00000063"
run_test "Local array"          "tests/mem_local_array.c"      "00000006"

# Pointers
run_test "Pointer deref"        "tests/mem_pointer_deref.c"    "0000002A"
run_test "Pointer write"        "tests/mem_pointer_write.c"    "00000064"
run_test "Pointer arith"        "tests/mem_pointer_arith.c"    "0000001E"
