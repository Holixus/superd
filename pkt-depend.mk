
DEPEND ?= .depend

depend: $(DEPEND) Makefile

$(DEPEND): $(SOURCES) Makefile
ifneq ($(SOURCES),)
	$(CPP) $(CFLAGS) $(IFLAGS) -MM $(SOURCES) > $(DEPEND)
else
	:> $(DEPEND)
endif


ifeq ($(filter clean git pull push,$(MAKECMDGOALS)),)
-include $(DEPEND)
endif
