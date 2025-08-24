# Makefile for asmhttpd with C helper
CC=gcc
CFLAGS=-O2 -fno-pie
LDFLAGS=-no-pie -nostartfiles

all: asmhttpd

asmhttpd: server.o security.o
	$(CC) $(LDFLAGS) -o $@ server.o security.o

server.o: server.asm
	nasm -f elf64 -g -F dwarf server.asm -o server.o

security.o: security.c
	$(CC) $(CFLAGS) -c security.c -o security.o

clean:
	rm -f asmhttpd *.o