CC=gcc
NASM=nasm
CFLAGS=-O2 -fno-pie -no-pie
LDFLAGS=-no-pie

all: asmhttpd

asmhttpd: server.o plugin.o
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

server.o: server.asm
	$(NASM) -f elf64 -g -F dwarf $< -o $@

plugin.o: plugin.c plugin_api.h
	$(CC) -c -O2 -fno-pie -no-pie plugin.c -o plugin.o

clean:
	rm -f *.o asmhttpd