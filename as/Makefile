# M65832 Assembler/Disassembler Makefile

CC ?= cc
AR ?= ar
CFLAGS ?= -O2 -Wall -Wextra -std=c11
PREFIX ?= /usr/local

# Common library (ISA definitions shared with LLVM backend)
COMMON_DIR = common
COMMON_LIB = $(COMMON_DIR)/libm65832.a
COMMON_INC = -I$(COMMON_DIR)

TARGETS = m65832as m65832dis

.PHONY: all clean install uninstall test debug check common

all: $(TARGETS)

# Build common library first
common:
	$(MAKE) -C $(COMMON_DIR)

$(COMMON_LIB): common

m65832as: m65832as.c $(COMMON_LIB)
	$(CC) $(CFLAGS) $(COMMON_INC) -o $@ $< $(COMMON_LIB)

m65832dis: m65832dis.c $(COMMON_LIB)
	$(CC) $(CFLAGS) $(COMMON_INC) -DM65832DIS_STANDALONE -o $@ $< $(COMMON_LIB)

clean:
	rm -f $(TARGETS) *.o
	rm -f test/*.bin test/*.hex
	$(MAKE) -C $(COMMON_DIR) clean

install: $(TARGETS)
	install -d $(PREFIX)/bin
	install -m 755 $(TARGETS) $(PREFIX)/bin/

uninstall:
	rm -f $(PREFIX)/bin/m65832as
	rm -f $(PREFIX)/bin/m65832dis

# Run test suite
test: $(TARGETS)
	@echo "Running tests..."
	@./run_tests.sh || echo "Create test files to run tests"

# Debug build
debug: CFLAGS = -g -O0 -Wall -Wextra -std=c11 -DDEBUG
debug: clean $(TARGETS)

# Static analysis (if cppcheck available)
check:
	@command -v cppcheck >/dev/null && cppcheck --enable=all --std=c11 m65832as.c m65832dis.c || echo "cppcheck not installed"
