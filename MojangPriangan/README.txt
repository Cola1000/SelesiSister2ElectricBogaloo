README.txt
===========
This package matches your glibc-style server.asm and fixes the crash causes:

1) write_str bug:
   - Before: called strlen with RDI=fd (segfault). 
   - Now: write_str saves fd, runs strlen on RSI, restores fd, then write().

2) log_line bug:
   - Was calling strlen with RDI=2 (fd), now uses write_str for METHOD and PATH.

3) filepath builder bug:
   - Was calling strlen(filepath) on an uninitialized buffer.
   - Now: takes strlen(docroot) and strlen(pathbuf), appends manually, and terminates.

4) main() arg parsing clobber:
   - Removed the accidental second 'mov r12, rdi / mov r13, rsi'. We keep the original argc/argv.

Features:
- Listen on port, accept, fork per connection
- Methods parsed: GET/POST/PUT/DELETE
- Static files (docroot), basic routing (/hello, /auth, /dyn/*)
- Basic Auth for /auth (admin/secret)
- Plugin C integration for /dyn/*
- Returns proper Content-Length and closes connection

Build:
  make

Run:
  ./asmhttpd -p 8080 -d ./www

Test:
  curl -v http://127.0.0.1:8080/
  curl -v http://127.0.0.1:8080/hello
  curl -v -H "Authorization: Basic YWRtaW46c2VjcmV0" http://127.0.0.1:8080/auth
  curl -v "http://127.0.0.1:8080/dyn/hello"
  curl -v "http://127.0.0.1:8080/dyn/add?a=2&b=40"

  # PUT/DELETE/POST samples
  curl -v -X PUT --data-binary @www/index.html http://127.0.0.1:8080/uploaded.html
  curl -v -X DELETE http://127.0.0.1:8080/uploaded.html
  curl -v -X POST --data "hello" http://127.0.0.1:8080/anything

Notes:
- If you still segfault, run under gdb and break on strlen to catch any remaining misuse:
    gdb --args ./asmhttpd -p 8080 -d ./www
    (gdb) run
    (gdb) bt
