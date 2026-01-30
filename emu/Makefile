# M65832 Emulator Makefile
#
# High-performance M65832 CPU emulator
# Builds both a library (libm65832emu.a) and standalone emulator (m65832emu)

CC ?= cc
AR ?= ar
CFLAGS ?= -O3 -Wall -Wextra -std=c99 -march=native
LDFLAGS ?=
PREFIX ?= /usr/local

# Source files
LIB_SRCS = m65832emu.c m65832_6502.c
SYS_SRCS = uart.c blkdev.c sandbox_filesystem.c system.c
EMU_SRCS = main.c
LIB_OBJS = $(LIB_SRCS:.c=.o)
SYS_OBJS = $(SYS_SRCS:.c=.o)
EMU_OBJS = $(EMU_SRCS:.c=.o)

# Targets
LIBRARY = libm65832emu.a
EMULATOR = m65832emu

.PHONY: all clean install uninstall test debug check profile

all: $(LIBRARY) $(EMULATOR)

# Library
$(LIBRARY): $(LIB_OBJS)
	$(AR) rcs $@ $^

# Standalone emulator
$(EMULATOR): $(EMU_OBJS) $(SYS_OBJS) $(LIBRARY)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(EMU_OBJS) $(SYS_OBJS) -L. -lm65832emu -lm

# Object files
%.o: %.c m65832emu.h
	$(CC) $(CFLAGS) -c -o $@ $<

# System objects depend on their headers
uart.o: uart.c uart.h m65832emu.h
blkdev.o: blkdev.c blkdev.h m65832emu.h
system.o: system.c system.h sandbox_filesystem.h uart.h blkdev.h m65832emu.h
sandbox_filesystem.o: sandbox_filesystem.c sandbox_filesystem.h system.h m65832emu.h
main.o: main.c m65832emu.h system.h uart.h blkdev.h

clean:
	rm -f $(LIBRARY) $(EMULATOR) *.o
	rm -f test/*.bin test/*.hex test/*.out

install: $(LIBRARY) $(EMULATOR)
	install -d $(PREFIX)/bin
	install -d $(PREFIX)/lib
	install -d $(PREFIX)/include
	install -m 755 $(EMULATOR) $(PREFIX)/bin/
	install -m 644 $(LIBRARY) $(PREFIX)/lib/
	install -m 644 m65832emu.h $(PREFIX)/include/

uninstall:
	rm -f $(PREFIX)/bin/$(EMULATOR)
	rm -f $(PREFIX)/lib/$(LIBRARY)
	rm -f $(PREFIX)/include/m65832emu.h

# Run test suite
test: $(EMULATOR)
	@echo "Running tests..."
	@./run_tests.sh

# Debug build (optimizations off, debug symbols on)
debug: CFLAGS = -g -O0 -Wall -Wextra -std=c99 -DDEBUG -fsanitize=address,undefined
debug: LDFLAGS = -fsanitize=address,undefined
debug: clean all

# Profile build (optimized with symbols)
profile: CFLAGS = -g -O3 -Wall -Wextra -std=c99 -march=native -pg
profile: LDFLAGS = -pg
profile: clean all

# Static analysis
check:
	@command -v cppcheck >/dev/null && cppcheck --enable=all --std=c99 $(LIB_SRCS) $(EMU_SRCS) || echo "cppcheck not installed"
