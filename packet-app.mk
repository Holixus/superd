MKINC := $(dir $(lastword $(MAKEFILE_LIST)))

include $(MKINC)pkt-head.mk


ifndef PROJECT_NAME
$(error PROJECT_NAME is not set)
endif


ifndef SOURCES
SOURCES := $(wildcard *.c)
endif


OBJS := $(SOURCES:.c=.o)


ifdef LIBDEPS
LDFLAGS += $(addprefix -l,$(LIBDEPS))
endif

TARGETS := $(PROJECT_NAME)


all: depend prepare $(TARGETS)

ifeq ($(package-prepare),)
prepare:;
else
$(call package-prepare)
endif


$(PROJECT_NAME): $(OBJS) Makefile
	$(CC) -o $@ $(OBJS) $(LDFLAGS) $(PACKET_LDFLAGS)

include $(MKINC)pkt-depend.mk

clean:
	rm -f $(DEPEND)
	rm -f $(OBJS) $(PROJECT_NAME)


gitignore-tail = $(file >> $@,/$(PROJECT_NAME))

include $(MKINC)pkt-rules.mk
