# Makefile for glibc-based asmhttpd
CC=gcc
CFLAGS=-O2 -fno-pie
LDFLAGS=-no-pie

all: asmhttpd

asmhttpd: server.o plugin.o
	$(CC) $(LDFLAGS) -o $@ server.o plugin.o

server.o: server.asm
	nasm -f elf64 -g -F dwarf server.asm -o server.o

plugin.o: plugin.c plugin_api.h
	$(CC) $(CFLAGS) -c plugin.c -o plugin.o

clean:
	rm -f asmhttpd *.o
