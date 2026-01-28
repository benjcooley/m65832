#!/bin/bash
# Data structure tests

run_test "Linked list"          "tests/ds_linked_list.c"    "0000003C"
run_test "List insert"          "tests/ds_list_insert.c"    "0000004B"
run_test "List reverse"         "tests/ds_list_reverse.c"   "0000001E"
run_test "Array sum ptr"        "tests/ds_array_sum.c"      "00000096"
run_test "Array find"           "tests/ds_array_find.c"     "00000003"
run_test "Array max"            "tests/ds_array_max.c"      "00000063"
run_test "Hash table"           "tests/ds_hashtable.c"      "0000002A"
run_test "Vector"               "tests/ds_vector.c"         "0000003C"
run_test "Stack"                "tests/ds_stack.c"          "0000001E"
run_test "Queue"                "tests/ds_queue.c"          "0000000A"
run_test "Binary search"        "tests/ds_binary_search.c"  "00000004"
run_test "Bubble sort"          "tests/ds_bubble_sort.c"    "0000000C"
