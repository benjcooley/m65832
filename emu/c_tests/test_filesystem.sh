#!/bin/bash
# Filesystem sandbox tests (system mode)

echo -n "  filesystem sandbox... "
if bash ./run_fs_tests.sh >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    ((PASSED++))
else
    echo -e "${RED}FAIL${NC}"
    ((FAILED++))
fi
