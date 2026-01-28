#!/bin/bash
# Integration tests - larger programs exercising multiple features

run_test "Calculator"           "tests/integ_calculator.c"      "0000000E"
run_test "State machine"        "tests/integ_state_machine.c"   "00000003"
run_test "FIFO buffer"          "tests/integ_ring_buffer.c"     "0000001E"
run_test "Bitfield ops"         "tests/integ_bitfield.c"        "00000025"
run_test "XOR checksum"         "tests/integ_crc.c"             "00000092"
run_test "Matrix multiply"      "tests/integ_matrix.c"          "00000013"
run_test "Find minimum"         "tests/integ_priority_queue.c"  "0000000A"
run_test "Count runs"           "tests/integ_encoder.c"         "00000004"
run_test "Histogram"            "tests/integ_histogram.c"       "00000003" 2000
run_test "Game score"           "tests/integ_game_score.c"      "00000096"
