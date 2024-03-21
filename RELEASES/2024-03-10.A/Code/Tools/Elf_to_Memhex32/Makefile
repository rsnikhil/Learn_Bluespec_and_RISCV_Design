# ================================================================

.PHONY: help
help:
	@echo "Targets:"
	@echo "    exe        Makes executable $(EXE)"

EXE=Elf_to_Memhex32.exe

.PHONY: exe
exe: $(EXE)

# ================================================================

ALL_H = Elf_to_Memhex32.h
ALL_C = Elf_to_Memhex32.c

# ----------------
# On Apple MacOS
ifeq ($(shell uname -s),Darwin)

# For include <gelf.h>, after 'brew install libelf'
CFLAGS += -I /opt/homebrew/include
CFLAGS += -I /opt/homebrew/include/libelf/

# For libelf.a on MacOS
LDFLAGS += -L /opt/homebrew/lib

endif

LDLIBS = -lelf -lm

# ================================================================
# Compile-and-link all to executable

$(EXE): $(ALL_C) $(ALL_H)
	$(CC)  $(CFLAGS) -o  $(EXE)  $(ALL_C)  $(LDFLAGS) $(LDLIBS)
	@echo "INFO: Executable $(EXE) created. Run it with --help for options."

# ================================================================
.PHONY: clean
clean:
	rm -r -f  *~

.PHONY: full_clean
full_clean: clean
	rm -r -f  $(EXE)
