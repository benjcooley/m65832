# Type Tests - Comprehensive byte/halfword/word operations
# Sourced by run_c_tests.sh

# Basic type loads and stores
run_test "Byte load"            "tests/type_byte_load.c"       "000000AB"
run_test "Byte store"           "tests/type_byte_store.c"      "00000042"
run_test "Byte adjacent"        "tests/type_byte_adjacent.c"   "00000001"
run_test "Half load"            "tests/type_half_load.c"       "0000ABCD"
run_test "Half store"           "tests/type_half_store.c"      "00001234"
run_test "Half adjacent"        "tests/type_half_adjacent.c"   "00000001"

# Sign extension
run_test "Sign extend byte"     "tests/type_sext_byte.c"       "FFFFFF80"
run_test "Sign extend half"     "tests/type_sext_half.c"       "FFFF8000"

# Zero extension  
run_test "Zero extend byte"     "tests/type_zext_byte.c"       "00000080"
run_test "Zero extend half"     "tests/type_zext_half.c"       "00008000"

# Original tests (backward compat)
run_test "Char arithmetic"      "tests/type_char.c"            "00000042"
run_test "Unsigned compare"     "tests/type_unsigned.c"        "00000001"
run_test "Signed negative"      "tests/type_signed_neg.c"      "00000001"
run_test "Type cast"            "tests/type_cast.c"            "00000034"
