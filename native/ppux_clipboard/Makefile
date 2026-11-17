# native/ppux_clipboard/Makefile
# Clipboard image reader for LuaJIT FFI.

CC ?= cc
CFLAGS ?= -O2 -fPIC -Wall -Wextra -std=c11
LDFLAGS_SHARED ?=
LIBS ?=

UNAME_S := $(shell uname -s 2>/dev/null || echo Unknown)

ifeq ($(OS),Windows_NT)
  TARGET := ppux_clipboard.dll
  SRCS := ppux_clipboard.c dib_to_rgba.c clipboard_win.c
  LDFLAGS_SHARED += -shared
  LIBS += -luser32
else ifeq ($(UNAME_S),Darwin)
  TARGET := libppux_clipboard.dylib
  SRCS := ppux_clipboard.c dib_to_rgba.c clipboard_macos.m
  CFLAGS += -fobjc-arc
  LDFLAGS_SHARED += -dynamiclib -install_name @rpath/libppux_clipboard.dylib
  LIBS += -framework AppKit -framework Foundation
else
  TARGET := libppux_clipboard.so
  SRCS := ppux_clipboard.c dib_to_rgba.c clipboard_linux.c
  LDFLAGS_SHARED += -shared
  PKG_CFLAGS := $(shell pkg-config --cflags wayland-client x11 2>/dev/null)
  PKG_LIBS := $(shell pkg-config --libs wayland-client x11 2>/dev/null)
  CFLAGS += $(PKG_CFLAGS)
  ifneq ($(strip $(PKG_LIBS)),)
    LIBS += $(PKG_LIBS)
  else
    LIBS += -lwayland-client -lX11
  endif
endif

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(SRCS) ppux_clipboard.h clipboard_internal.h dib_to_rgba.c
	$(CC) $(CFLAGS) $(LDFLAGS_SHARED) -o $@ $(SRCS) $(LIBS)

test_dib: test_dib.c dib_to_rgba.c ppux_clipboard.h
	$(CC) -O2 -Wall -Wextra -std=c11 -o $@ test_dib.c dib_to_rgba.c

test: test_dib
	./test_dib

clean:
	rm -f libppux_clipboard.so libppux_clipboard.dylib ppux_clipboard.dll test_dib
