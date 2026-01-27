# Bitwise Operation Tests
# Sourced by run_c_tests.sh

# Basic bitwise
run_test "AND"                "tests/bits_and.c"          "0000000F"
run_test "OR"                 "tests/bits_or.c"           "000000FF"
run_test "XOR"                "tests/bits_xor.c"          "00000055"
run_test "NOT"                "tests/bits_not.c"          "FFFFFFFF"

# Shifts
run_test "Shift left"         "tests/bits_shl.c"          "00000080"
run_test "Logical shift R"    "tests/bits_shr.c"          "00000002"
run_test "Arith shift R"      "tests/bits_ashr.c"         "FFFFFFFC"

# Advanced bit operations
run_test "Bit mask"           "tests/bits_mask.c"         "000000CD"
run_test "Bit set"            "tests/bits_set.c"          "00000011"
run_test "Bit toggle"         "tests/bits_toggle.c"       "000000F0"
run_test "Rotate left"        "tests/bits_rotate.c"       "34567812"
run_test "Count bits"         "tests/bits_count.c"        "00000008"
run_test "Extract field"      "tests/bits_extract.c"      "000000EF"
