# M65832 Common Library Makefile

CC ?= gcc
AR ?= ar
CFLAGS ?= -O2 -Wall -Wextra -std=c11

# Source files
SRCS = m65832_isa.c m65832_parser.c
OBJS = $(SRCS:.c=.o)

# Output library
LIB = libm65832.a

.PHONY: all clean

all: $(LIB)

$(LIB): $(OBJS)
	$(AR) rcs $@ $^

%.o: %.c m65832_isa.h m65832_parser.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(LIB)

# Test build
test: test_parser.c $(LIB)
	$(CC) $(CFLAGS) -o test_parser test_parser.c -L. -lm65832
