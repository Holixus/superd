
ifndef V
MAKEFLAGS += --silent
endif

.SUFFIXES:
.SUFFIXES: .o .c

.PHONY: clean all depend install git

ifndef DEBUG
PACKET_CFLAGS  ?= -std=gnu99 -Os -fvisibility=hidden -Werror -ffast-math -fmerge-all-constants -ffunction-sections -fdata-sections -fomit-frame-pointer -fno-unwind-tables -fno-asynchronous-unwind-tables -fmerge-all-constants -fno-ident
PACKET_LDFLAGS ?= -Wl,--gc-sections -Wl,-z,norelro -Wl,--build-id=none -z max-page-size=0x10
BIN_CFLAGS ?= -fwhole-program -s
else
PACKET_CFLAGS  ?= -std=gnu99 -O0 -g -Werror -ffast-math -fmerge-all-constants -ffunction-sections -fdata-sections
PACKET_LDFLAGS ?= -Wl,--gc-sections
BIN_CFLAGS ?=
endif

CFLAGS  += $(PACKET_CFLAGS) $(COMMON_CFLAGS) $(EXTRA_CFLAGS)

#LDFLAGS += $(PACKET_LDFLAGS)
