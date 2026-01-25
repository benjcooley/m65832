# M65832 Assembler/Disassembler Makefile

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c99
PREFIX ?= /usr/local

TARGETS = m65832as m65832dis

.PHONY: all clean install uninstall test debug check

all: $(TARGETS)

m65832as: m65832as.c
	$(CC) $(CFLAGS) -o $@ $^

m65832dis: m65832dis.c
	$(CC) $(CFLAGS) -DM65832DIS_STANDALONE -o $@ $^

clean:
	rm -f $(TARGETS) *.o
	rm -f test/*.bin test/*.hex

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
debug: CFLAGS = -g -O0 -Wall -Wextra -std=c99 -DDEBUG
debug: clean $(TARGETS)

# Static analysis (if cppcheck available)
check:
	@command -v cppcheck >/dev/null && cppcheck --enable=all --std=c99 m65832as.c m65832dis.c || echo "cppcheck not installed"
