include ../Include.mk

# Edit the following line as needed, to point at a clone of repo:
#    https://github.com/rsnikhil/Learn_Bluespec_and_RISCV_Design
BOOK_REPO ?= $(HOME)/Git/Learn_Bluespec_and_RISCV_Design



BOOK_REPO_CODE = $(BOOK_REPO)/Code

BSCPATH := $(BOOK_REPO_CODE)/src_Common:$(BSCPATH)
BSCPATH := $(BOOK_REPO_CODE)/src_Top:$(BSCPATH)
BSCPATH := $(BOOK_REPO_CODE)/vendor/bluespec_BSV_Additional_Libs:$(BSCPATH)

C_FILES += $(BOOK_REPO_CODE)/src_Top/C_Mems_Devices.c
C_FILES += $(BOOK_REPO_CODE)/src_Top/UART_model.c
