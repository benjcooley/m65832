# Struct Tests - Comprehensive struct access patterns
# Sourced by run_c_tests.sh

# Mixed-size struct fields
run_test "Struct mixed sizes"   "tests/struct_mixed_sizes.c"   "00000001"
run_test "Struct packed"        "tests/struct_packed.c"        "00000001"

# Original tests (backward compat)
run_test "Simple struct"        "tests/struct_simple.c"        "00000001"
run_test "Nested struct"        "tests/struct_nested.c"        "00000001"
run_test "Struct pointer"       "tests/struct_pointer.c"       "00000001"
run_test "Struct array"         "tests/struct_array.c"         "00000001"
