# Type Tests
# Sourced by run_c_tests.sh

run_test "Char arithmetic"    "tests/type_char.c"         "00000042"
run_test "Unsigned compare"   "tests/type_unsigned.c"     "00000001"
run_test "Signed negative"    "tests/type_signed_neg.c"   "00000001"
run_test "Type cast"          "tests/type_cast.c"         "00000034"
