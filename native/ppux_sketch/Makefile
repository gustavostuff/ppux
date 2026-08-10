# native/ppux_sketch/Makefile
# Build the sketch PNG helper shared library for LuaJIT FFI.

CC ?= cc
CFLAGS ?= -O2 -fPIC -Wall -Wextra -std=c11
LDFLAGS_SHARED ?=

UNAME_S := $(shell uname -s 2>/dev/null || echo Unknown)

ifeq ($(OS),Windows_NT)
  TARGET := ppux_sketch.dll
  LDFLAGS_SHARED += -shared
else ifeq ($(UNAME_S),Darwin)
  TARGET := libppux_sketch.dylib
  LDFLAGS_SHARED += -dynamiclib -install_name @rpath/libppux_sketch.dylib
else
  TARGET := libppux_sketch.so
  LDFLAGS_SHARED += -shared
endif

.PHONY: all clean

all: $(TARGET)

$(TARGET): ppux_sketch.c ppux_sketch.h
	$(CC) $(CFLAGS) $(LDFLAGS_SHARED) -o $@ ppux_sketch.c -lm

clean:
	rm -f libppux_sketch.so libppux_sketch.dylib ppux_sketch.dll
