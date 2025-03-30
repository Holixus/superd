MKINC := $(dir $(lastword $(MAKEFILE_LIST)))
include $(MKINC)pkt-head.mk


ifndef BIN_NAMES
$(error BIN_NAMES is not set)
endif


ifndef SOURCES
SOURCES := $(wildcard *.c)
endif


$(foreach bin,$(BIN_NAMES),$(eval SOURCES_$(bin) ?= $(bin).c))
$(foreach bin,$(BIN_NAMES),$(eval OBJS_$(bin) = $(SOURCES_$(bin):.c=.o)))

ifdef LIBDEPS
LDFLAGS += $(addprefix -l,$(LIBDEPS))
endif

TARGETS := $(BIN_NAMES)

define make_bin
$(1): $$(OBJS_$(1)) Makefile
	$$(CC) -o $$@ $$(OBJS) $$(OBJS_$$@) $$(BIN_CFLAGS) $$(LDFLAGS) $$(or $$(LDFLAGS_$$@),$$(PACKET_LDFLAGS)) $$(addprefix -l,$$(LIBDEPS_$$@))
endef


all: depend prepare $(TARGETS)

ifeq ($(package-prepare),)
prepare:;
else
$(call package-prepare)
endif

Makefile:

include $(MKINC)pkt-depend.mk


clean:
	rm -f $(DEPEND)
	rm -f *.o $(or $(clean_list),$(BIN_NAMES))


$(foreach bin,$(BIN_NAMES),$(eval $(call make_bin,$(bin))))

gitignore-tail = $(foreach bin,$(or $(clean_list),$(BIN_NAMES)),$(file >> $@,/$(bin)))

include $(MKINC)pkt-rules.mk
