README.txt
===========
Architecture: x86-64 Linux, System V ABI.
Core HTTP server written in NASM, calling glibc functions. Dynamic routing via a C plugin.

What’s implemented (core spec)
------------------------------
- Listen on a TCP port (bind/listen/accept).
- Fork per connection (each client handled by a child).
- Parse methods: GET / POST / PUT / DELETE.
- Serve static files from docroot (default ./www). Root "/" serves index.html.
- Simple routing:
  - /hello -> text body
  - /auth  -> Basic Auth (admin/secret)
  - /dyn/* -> C plugin (examples: /dyn/hello, /dyn/add?a=2&b=3)

Bonuses implemented
-------------------
- Integration with another binary: C plugin (`plugin.c`), called from assembly.
- Manual logging to stderr: `[METHOD PATH] STATUS BYTES` per request.
- Simple auth (/auth) and dynamic JSON endpoint (/dyn/add).
- README with clear tests.

Build
-----
make

Run
---
./asmhttpd -p 8080 -d ./www

Endpoints to try
----------------
# Static (HTML)
curl -v http://127.0.0.1:8080/

# Simple route
curl -v http://127.0.0.1:8080/hello

# Basic auth (admin/secret)
curl -v http://127.0.0.1:8080/auth
curl -v -H "Authorization: Basic YWRtaW46c2VjcmV0" http://127.0.0.1:8080/auth

# Dynamic plugin routes
curl -v "http://127.0.0.1:8080/dyn/hello"
curl -v "http://127.0.0.1:8080/dyn/add?a=5&b=7"

# POST -> writes body to docroot/post_result.txt
echo "hello body" | curl -v -X POST --data-binary @- http://127.0.0.1:8080/any
cat ./www/post_result.txt

# PUT / DELETE (file ops under DOCROOT)
echo "<h1>upload</h1>" | curl -v -X PUT --data-binary @- http://127.0.0.1:8080/uploaded.html
curl -v http://127.0.0.1:8080/uploaded.html
curl -v -X DELETE http://127.0.0.1:8080/uploaded.html

Notes
-----
- Directory traversal is guarded with a basic '..' check in paths.
- Content-Length is parsed for POST/PUT and /dyn/*; body copy is bounded.
- Content-Type guessed for .html else text/plain.
- This is a minimal educational server; for real deployments, prefer a hardened web server.
