
.c.o:
	$(CC) -c -o $@ $(CFLAGS) $(IFLAGS) $<

git: .gitignore

.gitignore: Makefile
	$(file > $@,*.[ao])
	$(file >> $@,*.so)
	$(file >> $@,/$(DEPEND))
	$(call gitignore-tail)
