#!/bin/sh
set -e

./tb/run_tests.sh coprocessor mx65_illegal interleave coprocessor_soak maincore_timeslice
