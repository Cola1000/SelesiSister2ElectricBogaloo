Web Server in Assembly (x86-64 Linux)
==================================================================

- Architecture   : x86-64 (System V ABI) di Linux
- Assembler      : NASM
- Linker         : GCC/ld
- Status         : Demo anu bekerja teh forking per request, routing, static files, otentikasi basic, templet simpel, jeung integrasi C plugin. 

Bjir aku orang sunda tapi gabisa bahasa Sunda :v


Summary
-------
asm-httpd is a tiny HTTP/1.1 server written directly in x86-64 assembly (not generated
from C). It listens on a TCP port, forks a child process per client connection, parses
HTTP methods (GET, POST, PUT, DELETE), serves static files from a document root, and
dispatches certain paths via a dynamic plugin written in C and linked in at build time.

A minimal “framework” is included via plugin_api.h + plugin.c so you can add handlers
under /dyn/* without touching the assembly core.

Features (Wajib)
-------------------
1) Listen on a specified port (default 8080).
2) Fork a child process per incoming connection (parent continues accept loop).
3) Parse HTTP methods: GET, POST, PUT, DELETE.
4) Serve static files from a local docroot (default ./www).
5) Simple routing by path:
   - "/" (serves ./www/index.html)
   - "/hello" (example plain-text response from assembly)
   - "/auth"  (Basic Auth demo; user: admin, pass: secret)
   - "/dyn/*" (goes to C plugin; example handlers provided)
   - fallback to static-file serving under docroot

Bonuses Implemented
-------------------
[Integrasi Binary Lain] (Linking Binary)
- The assembly server calls into a C plugin via: extern plugin_dispatch(...)
- Example handlers:
  * /dyn/hello           -> "Hello from C plugin!"
  * /dyn/add?a=2&b=40    -> JSON {"a":2,"b":40,"sum":42}

[Port Forwarding & Demo]
- Step-by-step instructions for exposing the local server using:
  * SSH reverse tunnel, or
  * cloudflared, or
  * ngrok
- Get the public URL, then do whatever do f*** you want with it.

[KREATIVITAS]
- Basic Authentication on /auth:
  * Authorization: Basic YWRtaW46c2VjcmV0 (admin:secret)
  * Sends 401 with WWW-Authenticate if missing/invalid.
- Manual logging (example to stderr; can be redirected to a file).
- Super-simple templating for ".tmpl" files (placeholders like {{METHOD}}, {{PATH}}, {{NOW}}).

[Framework (Eksperimen)]
- plugin_api.h + plugin.c provide a tiny handler table for /dyn/* so you can expand
  functionality in C without editing the assembly core.

[Deploy (Eksperimen)]
- Systemd unit, NGINX reverse proxy, and Let’s Encrypt (certbot) instructions included.

Repository Layout
-----------------
```
asm-httpd/
├─ Makefile
├─ README.md
├─ server.asm         (assembly HTTP core; socket/bind/listen/accept/fork)
├─ plugin_api.h       (C “framework” interface)
├─ plugin.c           (example handlers for /dyn/*)
├─ www/
│  ├─ index.html
│  ├─ hello.html
│  ├─ secret.html
│  └─ demo.tmpl
└─ deploy/
   ├─ asm-httpd.service        (systemd unit)
   ├─ nginx.conf.example       (reverse proxy)
   └─ cloudflared.yaml.example
```

Build (Arch / Debian / Ubuntu)
------------------------------
```
Dependencies:
  Arch   : sudo pacman -S nasm gcc make
  Ubuntu : sudo apt-get install -y nasm build-essential make
  Debian : sudo apt-get install -y nasm build-essential make

Build:
  make

This produces: ./asmhttpd

Run
---
  ./asmhttpd -p 8080 -d ./www
```
(If argument parsing is simplified in your version, default is port 8080 and docroot ./www.)

Quick Test
----------
```
  curl -v http://127.0.0.1:8080/
  curl -v http://127.0.0.1:8080/hello
  curl -v http://127.0.0.1:8080/auth                # 401 without Authorization
  curl -v -H "Authorization: Basic YWRtaW46c2VjcmV0" http://127.0.0.1:8080/auth
  curl -v "http://127.0.0.1:8080/dyn/hello"
  curl -v "http://127.0.0.1:8080/dyn/add?a=2&b=40"
  curl -X POST   -d 'abc' http://127.0.0.1:8080/echo
  curl -X PUT    -d 'xyz' http://127.0.0.1:8080/echo
  curl -X DELETE      http://127.0.0.1:8080/upload/somefile
```
Open in Chrome/Firefox:
  http://localhost:8080/

Routing Map (Examples)
----------------------
```
  /                    -> ./www/index.html (if path ends with /, appends index.html)
  /hello               -> "Hello from asm-httpd" (assembly response)
  /auth                -> 401 unless Basic admin:secret
  /dyn/hello           -> C plugin: plain-text greeting
  /dyn/add?a=2&b=40    -> C plugin: JSON sum
  /anything-else       -> static file lookup under docroot
```
Static File Serving
-------------------
- Files are read from the configured docroot (default ./www).
- If the requested path ends in "/", the server appends "index.html".
- Very simple content-type branching: .html and .tmpl -> text/html, otherwise text/plain.
- Demo templates ending in .tmpl may be processed for placeholders (simple sample).

Basic Authentication (Demo)
---------------------------
- Path: /auth
- Scheme: Basic
- Credentials: admin / secret
- Base64: Authorization: Basic YWRtaW46c2VjcmV0
- On missing/invalid credentials, server returns 401 and WWW-Authenticate header.

Logging
-------
- Minimal example logs to stderr: method, path, status, bytes, pid (extend as needed).
- Redirect to a file if desired:
  ./asmhttpd 2>>asmhttpd.log

Templating (Very Simple)
------------------------
- Files ending with .tmpl can include placeholders like:
  {{METHOD}}  {{PATH}}  {{NOW}}
- The demo implementation is intentionally minimal and can be extended easily.

C Plugin Interface (Mini-Framework)
-----------------------------------
```
Header: plugin_api.h
Function:
  int plugin_dispatch(const char* method,
                      const char* path,
                      const char* query,   // may be NULL
                      const char* body,    // request body
                      int body_len,
                      char* out,           // output buffer
                      int out_cap,
                      int* out_status,     // set HTTP status (e.g., 200, 400, 404)
                      const char** out_ct  // set content-type string
  );
```

- The assembly core routes any path that starts with /dyn to plugin_dispatch.
- Extend plugin.c with new handlers to add features without changing server.asm.

Security Notes & Limitations
----------------------------
- Directory traversal: a basic ".." check is included; consider hardening further.
- Request body size: currently limited (~64 KB in demo); adjust as necessary.
- HTTP/1.1 features: no persistent connections, no chunked encoding; adequate for
  demos and modern browsers/curl in simple scenarios.
- Error handling is pragmatic/minimal for clarity.

Port Forwarding & Public Demo
-----------------------------
```
Option A: SSH Reverse Tunnel (need a VPS)
  ssh -N -R 0.0.0.0:18080:127.0.0.1:8080 user@your.vps.example
  Public access: http://your.vps.example:18080/

Option B: Cloudflared (no VPS needed)
  cloudflared tunnel --url http://localhost:8080
  => Copy the https://<random>.trycloudflare.com URL

Option C: ngrok
  ngrok http 8080
  => Copy the forwarded https URL
```
<!-- Send the public URL yourself to Edbert via LINE (yenyenhui) or Discord (wazeazure). -->

Production Deploy (Experiment)
------------------------------
1) Systemd unit (deploy/asm-httpd.service)
    ```
   [Unit]
   Description=asm-httpd
   After=network.target

   [Service]
   ExecStart=/opt/asm-httpd/asmhttpd -p 8080 -d /opt/asm-httpd/www
   User=www-data
   Restart=always

   [Install]
   WantedBy=multi-user.target

   Commands:
     sudo cp asmhttpd /opt/asm-httpd/
     sudo cp -r www /opt/asm-httpd/
     sudo cp deploy/asm-httpd.service /etc/systemd/system/
     sudo systemctl daemon-reload
     sudo systemctl enable --now asm-httpd
    ```

2) NGINX reverse proxy (deploy/nginx.conf.example)
    ```
   server {
       listen 80;
       server_name your.domain;

       location / {
           proxy_pass http://127.0.0.1:8080;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
       }
   }

   Enable + reload:
     sudo ln -s /etc/nginx/sites-available/asm-httpd /etc/nginx/sites-enabled/
     sudo nginx -t && sudo systemctl reload nginx
    ```
3) Let’s Encrypt (certbot)
    ```
   Ubuntu/Debian:
     sudo apt-get install -y certbot python3-certbot-nginx
     sudo certbot --nginx -d your.domain
    ```

References / Credits
--------------------
- Linux man-pages: socket(2), bind(2), listen(2), accept(2), fork(2), read(2), write(2), open(2), lseek(2)
- RFC 9110 (HTTP Semantics) and RFC 9112 (HTTP/1.1)
- System V AMD64 ABI (calling convention)

Notes
-----
- Example code aims for clarity over completeness. Harden and extend as needed for your use case.
- Default port/docroot may be hardcoded in the simplest build; you can extend argv parsing in ASM.

Enjoy hacking! :)
