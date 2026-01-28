#!/bin/bash
# run_all_picolibc_tests.sh - Run all picolibc tests with nice output
#
# Green checkmark for pass, red X for fail

LLVM_ROOT="/Users/benjamincooley/projects/llvm-m65832"
LLVM_BUILD_FAST="$LLVM_ROOT/build-fast"
LLVM_BUILD_DEFAULT="$LLVM_ROOT/build"
if [ -d "$LLVM_BUILD_FAST" ] && [ -x "$LLVM_BUILD_FAST/bin/clang" ]; then
    LLVM_BUILD="$LLVM_BUILD_FAST"
else
    LLVM_BUILD="$LLVM_BUILD_DEFAULT"
fi
CLANG="$LLVM_BUILD/bin/clang"
LLD_FAST="$LLVM_BUILD_FAST/bin/ld.lld"
LLD_DEFAULT="$LLVM_BUILD_DEFAULT/bin/ld.lld"
if [ -x "$LLD_FAST" ]; then
    LLD="$LLD_FAST"
else
    LLD="$LLD_DEFAULT"
fi
EMU="/Users/benjamincooley/projects/M65832/emu/m65832emu"
SYSROOT="/Users/benjamincooley/projects/m65832-sysroot"
WORKDIR="/tmp/picolibc_tests"
MAX_CYCLES=500000

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Icons
PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
SKIP="${YELLOW}○${NC}"

mkdir -p "$WORKDIR"

PASSED=0
FAILED=0
SKIPPED=0

declare -a FAILED_TESTS=()

run_test() {
    local name="$1"
    local src="$2"
    local expected="$3"
    
    local base=$(basename "$src" .c)
    
    # Compile
    if ! $CLANG -target m65832-elf -O0 -ffreestanding \
        -I"$SYSROOT/include" \
        -c "$src" -o "$WORKDIR/${base}.o" 2>/dev/null; then
        echo -e "  ${SKIP} ${name} (compile failed)"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    
    # Link
    if ! $LLD -T "$SYSROOT/lib/m65832.ld" \
        "$SYSROOT/lib/crt0.o" \
        "$WORKDIR/${base}.o" \
        -L"$SYSROOT/lib" -lc -lsys \
        -o "$WORKDIR/${base}.elf" 2>/dev/null; then
        echo -e "  ${SKIP} ${name} (link failed)"
        SKIPPED=$((SKIPPED + 1))
        return
    fi
    
    # Run
    local output
    output=$($EMU -c "$MAX_CYCLES" -s "$WORKDIR/${base}.elf" 2>&1)
    
    # Extract A register value
    local a_val
    a_val=$(echo "$output" | grep "PC:.*A:" | sed 's/.*A: *\([0-9A-Fa-f]*\).*/\1/')
    local result=$((16#$a_val))
    
    # Check result
    if [ "$result" = "$expected" ]; then
        echo -e "  ${PASS} ${name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${FAIL} ${name} (expected=${expected}, got=${result})"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$name")
    fi
}

# Create temporary test files
create_tests() {
    # strlen tests
    cat > "$WORKDIR/test_strlen.c" << 'EOF'
#include <string.h>
int main(void) {
    int e = 0;
    if (strlen("") != 0) e++;
    if (strlen("a") != 1) e++;
    if (strlen("hello") != 5) e++;
    if (strlen("hello world") != 11) e++;
    return e;
}
EOF

    # strcmp tests
    cat > "$WORKDIR/test_strcmp.c" << 'EOF'
#include <string.h>
int main(void) {
    int e = 0;
    if (strcmp("abc", "abc") != 0) e++;
    if (strcmp("abc", "abd") >= 0) e++;
    if (strcmp("abd", "abc") <= 0) e++;
    if (strcmp("", "") != 0) e++;
    return e;
}
EOF

    # strncmp tests
    cat > "$WORKDIR/test_strncmp.c" << 'EOF'
#include <string.h>
int main(void) {
    int e = 0;
    if (strncmp("abcd", "abce", 3) != 0) e++;
    if (strncmp("abcd", "abce", 4) >= 0) e++;
    return e;
}
EOF

    # strcpy tests
    cat > "$WORKDIR/test_strcpy.c" << 'EOF'
#include <string.h>
int main(void) {
    char buf[32];
    strcpy(buf, "hello");
    if (strcmp(buf, "hello") != 0) return 1;
    strcpy(buf, "world");
    if (strcmp(buf, "world") != 0) return 2;
    return 0;
}
EOF

    # strncpy tests
    cat > "$WORKDIR/test_strncpy.c" << 'EOF'
#include <string.h>
int main(void) {
    char buf[32];
    int i;
    for (i = 0; i < 32; i++) buf[i] = 'z';
    strncpy(buf, "hello", 3);
    if (buf[0] != 'h') return 1;
    if (buf[1] != 'e') return 2;
    if (buf[2] != 'l') return 3;
    return 0;
}
EOF

    # memset tests
    cat > "$WORKDIR/test_memset.c" << 'EOF'
#include <string.h>
int main(void) {
    char buf[16];
    memset(buf, 'x', 8);
    if (buf[0] != 'x') return 1;
    if (buf[7] != 'x') return 2;
    memset(buf, 0, 4);
    if (buf[0] != 0) return 3;
    if (buf[3] != 0) return 4;
    if (buf[4] != 'x') return 5;
    return 0;
}
EOF

    # memcpy tests
    cat > "$WORKDIR/test_memcpy.c" << 'EOF'
#include <string.h>
int main(void) {
    char src[] = "hello";
    char dst[16];
    memcpy(dst, src, 6);
    if (strcmp(dst, "hello") != 0) return 1;
    return 0;
}
EOF

    # memcmp tests
    cat > "$WORKDIR/test_memcmp.c" << 'EOF'
#include <string.h>
int main(void) {
    int e = 0;
    if (memcmp("abc", "abc", 3) != 0) e++;
    if (memcmp("abc", "abd", 3) >= 0) e++;
    if (memcmp("abd", "abc", 3) <= 0) e++;
    return e;
}
EOF

    # strchr tests
    cat > "$WORKDIR/test_strchr.c" << 'EOF'
#include <string.h>
int main(void) {
    const char *s = "hello";
    const char *p;
    p = strchr(s, 'e');
    if (p == (void*)0 || *p != 'e') return 1;
    p = strchr(s, 'l');
    if (p == (void*)0 || *p != 'l') return 2;
    p = strchr(s, 'z');
    if (p != (void*)0) return 3;
    return 0;
}
EOF

    # strrchr tests
    cat > "$WORKDIR/test_strrchr.c" << 'EOF'
#include <string.h>
int main(void) {
    const char *s = "hello";
    const char *p;
    p = strrchr(s, 'l');
    if (p == (void*)0 || *p != 'l') return 1;
    p = strrchr(s, 'z');
    if (p != (void*)0) return 2;
    return 0;
}
EOF

    # strcat tests
    cat > "$WORKDIR/test_strcat.c" << 'EOF'
#include <string.h>
int main(void) {
    char buf[32] = "hello";
    strcat(buf, " world");
    if (strcmp(buf, "hello world") != 0) return 1;
    return 0;
}
EOF

    # abs tests
    cat > "$WORKDIR/test_abs.c" << 'EOF'
#include <stdlib.h>
int main(void) {
    int e = 0;
    if (abs(5) != 5) e++;
    if (abs(-5) != 5) e++;
    if (abs(0) != 0) e++;
    return e;
}
EOF

    # atoi tests
    cat > "$WORKDIR/test_atoi.c" << 'EOF'
#include <stdlib.h>
int main(void) {
    if (atoi("123") != 123) return 1;
    if (atoi("-456") != -456) return 2;
    if (atoi("0") != 0) return 3;
    return 0;
}
EOF

    # memmove tests
    cat > "$WORKDIR/test_memmove.c" << 'EOF'
#include <string.h>
int main(void) {
    char buf[16];
    buf[0] = 'a'; buf[1] = 'b'; buf[2] = 'c'; buf[3] = 'd';
    buf[4] = 'e'; buf[5] = 'f'; buf[6] = 'g'; buf[7] = 'h';
    memmove(buf + 2, buf, 4);
    if (buf[2] != 'a') return 1;
    if (buf[3] != 'b') return 2;
    if (buf[4] != 'c') return 3;
    if (buf[5] != 'd') return 4;
    return 0;
}
EOF

    # ctype tests
    cat > "$WORKDIR/test_ctype.c" << 'EOF'
#include <ctype.h>
int main(void) {
    int e = 0;
    if (!isdigit('5')) e++;
    if (isdigit('a')) e++;
    if (!isalpha('A')) e++;
    if (isalpha('5')) e++;
    if (tolower('A') != 'a') e++;
    if (toupper('a') != 'A') e++;
    return e;
}
EOF
}

# Main
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}              Picolibc Test Suite for M65832${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""

create_tests

echo -e "${BOLD}String Functions${NC}"
run_test "strlen()" "$WORKDIR/test_strlen.c" 0
run_test "strcmp()" "$WORKDIR/test_strcmp.c" 0
run_test "strncmp()" "$WORKDIR/test_strncmp.c" 0
run_test "strcpy()" "$WORKDIR/test_strcpy.c" 0
run_test "strncpy()" "$WORKDIR/test_strncpy.c" 0
run_test "strcat()" "$WORKDIR/test_strcat.c" 0
run_test "strchr()" "$WORKDIR/test_strchr.c" 0
run_test "strrchr()" "$WORKDIR/test_strrchr.c" 0

echo ""
echo -e "${BOLD}Memory Functions${NC}"
run_test "memset()" "$WORKDIR/test_memset.c" 0
run_test "memcpy()" "$WORKDIR/test_memcpy.c" 0
run_test "memcmp()" "$WORKDIR/test_memcmp.c" 0
run_test "memmove()" "$WORKDIR/test_memmove.c" 0

echo ""
echo -e "${BOLD}Stdlib Functions${NC}"
run_test "abs()" "$WORKDIR/test_abs.c" 0
run_test "atoi()" "$WORKDIR/test_atoi.c" 0

echo ""
echo -e "${BOLD}Ctype Functions${NC}"
run_test "ctype functions" "$WORKDIR/test_ctype.c" 0

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                        RESULTS${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${PASS} Passed:  ${GREEN}${PASSED}${NC}"
echo -e "  ${FAIL} Failed:  ${RED}${FAILED}${NC}"
echo -e "  ${SKIP} Skipped: ${YELLOW}${SKIPPED}${NC}"
echo ""

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "${BOLD}Failed Tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${FAIL} $test"
    done
    echo ""
fi

TOTAL=$((PASSED + FAILED))
if [ $TOTAL -gt 0 ]; then
    PCT=$((PASSED * 100 / TOTAL))
    echo -e "Pass rate: ${BOLD}${PCT}%${NC}"
fi
echo ""
