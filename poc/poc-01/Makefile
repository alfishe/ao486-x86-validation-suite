# POC-01 Makefile
# Builds DOS .COM executables for UART testing

NASM := nasm
NASM_FLAGS := -f bin

.PHONY: all clean

all: push.com server.com

push.com: push.asm
	$(NASM) $(NASM_FLAGS) -o $@ $<

server.com: server.asm
	$(NASM) $(NASM_FLAGS) -o $@ $<

clean:
	rm -f *.com
