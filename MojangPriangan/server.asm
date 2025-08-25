%define SYSCALL_READ        0
%define SYSCALL_WRITE       1
%define SYSCALL_OPEN        2
%define SYSCALL_CLOSE       3
%define SYSCALL_SOCKET      41
%define SYSCALL_ACCEPT      43
%define SYSCALL_BIND        49
%define SYSCALL_LISTEN      50
%define SYSCALL_FORK        57
%define SYSCALL_EXIT        60
%define SYSCALL_UNLINK      87

%define AF_INET     2
%define SOCK_STREAM 1
%define O_RDONLY    0
%define O_WRONLY    1
%define O_CREAT     64
%define O_TRUNC     512

section .data
    ; Method constants for quick comparison
    GET_METHOD      dd 'GET '
    POST_METHOD     dd 'POST'
    PUT_METHOD      dd 'PUT '
    DELETE_METHOD   dd 'DELE' ; 'DELETE'

    clen_key        db 'Content-Length: ',0

    ; Default files and paths
    file_root       db 'www/index.html', 0
    post_filename   db 'www/post_result.txt', 0
    www_prefix      db 'www/', 0
    len_www_prefix  equ $ - www_prefix

    ; HTTP Responses
    http_200        db 'HTTP/1.1 200 OK', 13, 10, 'Content-Type: text/html', 13, 10, 13, 10
    len_200         equ $ - http_200

    http_201        db 'HTTP/1.1 201 Created', 13, 10, 13, 10, 'File created successfully.'
    len_201         equ $ - http_201

    http_200_del    db 'HTTP/1.1 200 OK', 13, 10, 13, 10, 'File deleted successfully.'
    len_200_del     equ $ - http_200_del

    http_400        db 'HTTP/1.1 400 Bad Request', 13, 10, 13, 10, '<h1>400 Bad Request</h1>'
    len_400         equ $ - http_400

    http_404        db 'HTTP/1.1 404 Not Found', 13, 10, 13, 10, '<h1>404 Not Found</h1>'
    len_404         equ $ - http_404

    http_405        db 'HTTP/1.1 405 Method Not Allowed', 13, 10, 13, 10, '<h1>405 Method Not Allowed</h1>'
    len_405         equ $ - http_405

    ; 200 text/plain and 200 application/json
    http_200_text   db 'HTTP/1.1 200 OK', 13,10, 'Content-Type: text/plain', 13,10,13,10
    len_200_text    equ $ - http_200_text
    http_200_json   db 'HTTP/1.1 200 OK', 13,10, 'Content-Type: application/json', 13,10,13,10
    len_200_json    equ $ - http_200_json

    ; 401 with WWW-Authenticate (for /auth)
    http_401        db 'HTTP/1.1 401 Unauthorized', 13,10, \
                        'WWW-Authenticate: Basic realm="asmhttpd"', 13,10,13,10, \
                        'Unauthorized'
    len_401         equ $ - http_401

    ; small HTML page for /auth success
    auth_ok_page    db '<!doctype html><html><body><h1>Auth OK</h1></body></html>'
    len_auth_ok_page equ $ - auth_ok_page

    ; dyn hello body
    dyn_hello_body  db 'Hello from dyn'
    len_dyn_hello_body equ $ - dyn_hello_body

    ; Authorization header key and base64(admin:secret)
    auth_hdr_key    db 'Authorization: Basic ',0
    auth_b64_good   db 'YWRtaW46c2VjcmV0',0

; Simple dynamic HTML body for /hello
hello_body      db '<!doctype html><html><body><h1>This SHIT SO HARD WTFFF</h1></body></html>'
len_hello_body  equ $ - hello_body


section .bss
    sockaddr_in     resb 16
    request_buffer  resb 2048
    file_buffer     resb 8192
    path_buffer     resb 256

section .text
global _start
extern is_path_safe ; External C function

_start:
    ; --- Create Socket ---
    mov     rax, SYSCALL_SOCKET
    mov     rdi, AF_INET
    mov     rsi, SOCK_STREAM
    xor     rdx, rdx
    syscall
    mov     r12, rax ; Save server_fd in r12

    ; --- Prepare and Bind Address ---
    mov     word [sockaddr_in], AF_INET
    mov     word [sockaddr_in+2], 0x901F ; Port 8080, big-endian
    mov     dword [sockaddr_in+4], 0      ; Bind to any IP
    mov     rax, SYSCALL_BIND
    mov     rdi, r12
    mov     rsi, sockaddr_in
    mov     rdx, 16
    syscall

    ; --- Listen for Connections ---
    mov     rax, SYSCALL_LISTEN
    mov     rdi, r12
    mov     rsi, 10 ; Backlog
    syscall

.accept_loop:
    mov     rax, SYSCALL_ACCEPT
    mov     rdi, r12
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    mov     r13, rax ; Save client_fd in r13

    ; --- Fork for Concurrency ---
    mov     rax, SYSCALL_FORK
    syscall
    cmp     rax, 0
    je      .child_process

.parent_process:
    mov     rax, SYSCALL_CLOSE
    mov     rdi, r13 ; Close client_fd in parent
    syscall
    jmp     .accept_loop

.child_process:
    mov     rax, SYSCALL_CLOSE
    mov     rdi, r12 ; Close server_fd in child
    syscall

    ; --- Read request from client ---
    mov     rax, SYSCALL_READ
    mov     rdi, r13
    mov     rsi, request_buffer
    mov     rdx, 2048
    syscall
    cmp     rax, 0
    jle     .close_and_exit ; If read failed or empty, just exit

    mov     r15, rax ; Save request length in r15

    ; --- Parse Method ---
    mov     eax, [request_buffer]
    cmp     eax, [GET_METHOD]
    je      .handle_get
    cmp     eax, [POST_METHOD]
    je      .handle_post
    cmp     eax, [PUT_METHOD]
    je      .handle_put
    cmp     eax, [DELETE_METHOD]
    je      .handle_delete
    jmp     .handle_405 ; Unknown method

; --- Handlers ---
.handle_get:
    lea     rsi, [request_buffer + 4] ; Path starts after "GET "

    ; === /auth (Basic admin:secret) ===
    push    rsi
    mov     rbx, rsi
    cmp     byte [rbx+0], '/'
    jne     .route_auth_skip
    cmp     byte [rbx+1], 'a'
    jne     .route_auth_skip
    cmp     byte [rbx+2], 'u'
    jne     .route_auth_skip
    cmp     byte [rbx+3], 't'
    jne     .route_auth_skip
    cmp     byte [rbx+4], 'h'
    jne     .route_auth_skip
    ; next must be space or '?' (end of path)
    mov     al, byte [rbx+5]
    cmp     al, ' '
    je      .route_auth_handle
    cmp     al, '?'
    jne     .route_auth_skip

.route_auth_handle:
    ; Find "Authorization: Basic "
    lea     rdi, [rel auth_hdr_key]
    lea     rsi, [request_buffer]
    call    find_header_value
    jc      .auth_send_401

    ; Skip spaces after header key
.auth_sp:
    cmp     byte [rsi], ' '
    jne     .auth_cmp
    inc     rsi
    jmp     .auth_sp

    ; Compare with base64("admin:secret")
.auth_cmp:
    lea     rdx, [rel auth_b64_good]
.ac_loop:
    mov     al, byte [rdx]
    cmp     al, 0
    je      .auth_ok
    cmp     al, byte [rsi]
    jne     .auth_send_401
    inc     rdx
    inc     rsi
    jmp     .ac_loop

.auth_ok:
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, http_200
    mov     rdx, len_200
    syscall

    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, auth_ok_page
    mov     rdx, len_auth_ok_page
    syscall

    pop     rsi
    jmp     .close_and_exit

.auth_send_401:
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, http_401
    mov     rdx, len_401
    syscall
    pop     rsi
    jmp     .close_and_exit

.route_auth_skip:
    pop     rsi


    ; === /dyn/hello (text/plain) ===
    push    rsi
    mov     rbx, rsi
    cmp     byte [rbx+0], '/'
    jne     .route_dynhello_skip
    cmp     byte [rbx+1], 'd'
    jne     .route_dynhello_skip
    cmp     byte [rbx+2], 'y'
    jne     .route_dynhello_skip
    cmp     byte [rbx+3], 'n'
    jne     .route_dynhello_skip
    cmp     byte [rbx+4], '/'
    jne     .route_dynhello_skip
    cmp     byte [rbx+5], 'h'
    jne     .route_dynhello_skip
    cmp     byte [rbx+6], 'e'
    jne     .route_dynhello_skip
    cmp     byte [rbx+7], 'l'
    jne     .route_dynhello_skip
    cmp     byte [rbx+8], 'l'
    jne     .route_dynhello_skip
    cmp     byte [rbx+9], 'o'
    jne     .route_dynhello_skip
    mov     al, byte [rbx+10]
    cmp     al, ' '
    jne     .route_dynhello_skip

    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, http_200_text
    mov     rdx, len_200_text
    syscall

    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, dyn_hello_body
    mov     rdx, len_dyn_hello_body
    syscall

    pop     rsi
    jmp     .close_and_exit

.route_dynhello_skip:
    pop     rsi

    ; === /dyn/add?a=..&b=.. (application/json) ===
    push    rsi
    mov     rbx, rsi
    cmp     byte [rbx+0], '/'
    jne     .route_dynadd_skip
    cmp     byte [rbx+1], 'd'
    jne     .route_dynadd_skip
    cmp     byte [rbx+2], 'y'
    jne     .route_dynadd_skip
    cmp     byte [rbx+3], 'n'
    jne     .route_dynadd_skip
    cmp     byte [rbx+4], '/'
    jne     .route_dynadd_skip
    cmp     byte [rbx+5], 'a'
    jne     .route_dynadd_skip
    cmp     byte [rbx+6], 'd'
    jne     .route_dynadd_skip
    cmp     byte [rbx+7], 'd'
    jne     .route_dynadd_skip
    cmp     byte [rbx+8], '?'
    jne     .route_dynadd_skip

    ; Parse query
    lea     rsi, [rbx+9]       ; after "add?"
    ; a=
    cmp     byte [rsi], 'a'
    jne     .route_dynadd_skip
    inc     rsi
    cmp     byte [rsi], '='
    jne     .route_dynadd_skip
    inc     rsi
    call    parse_int
    mov     r8, rax            ; a

    ; find b=
.da_seek_b:
    cmp     byte [rsi], 'b'
    je      .da_b_eq
    cmp     byte [rsi], 0
    je      .route_dynadd_skip
    inc     rsi
    jmp     .da_seek_b

.da_b_eq:
    inc     rsi
    cmp     byte [rsi], '='
    jne     .route_dynadd_skip
    inc     rsi
    call    parse_int
    mov     r9, rax            ; b

    ; sum = a + b
    mov     rax, r8
    add     rax, r9

    ; Build JSON into file_buffer: {"a":A,"b":B,"sum":S}\n
    mov     rdi, file_buffer
    mov     byte [rdi+0], '{'
    mov     byte [rdi+1], '"'
    mov     byte [rdi+2], 'a'
    mov     byte [rdi+3], '"'
    mov     byte [rdi+4], ':'
    lea     rsi, [rdi+5]
    mov     rbx, r8
    call    u32_to_dec
    mov     byte [rsi], ','
    inc     rsi
    mov     byte [rsi], '"'
    inc     rsi
    mov     byte [rsi], 'b'
    inc     rsi
    mov     byte [rsi], '"'
    inc     rsi
    mov     byte [rsi], ':'
    inc     rsi
    mov     rbx, r9
    call    u32_to_dec
    mov     byte [rsi], ','
    inc     rsi
    mov     byte [rsi], '"'
    inc     rsi
    mov     byte [rsi], 's'
    inc     rsi
    mov     byte [rsi], 'u'
    inc     rsi
    mov     byte [rsi], 'm'
    inc     rsi
    mov     byte [rsi], '"'
    inc     rsi
    mov     byte [rsi], ':'
    inc     rsi
    mov     rbx, rax
    call    u32_to_dec
    mov     byte [rsi], '}'
    inc     rsi
    mov     byte [rsi], 10
    inc     rsi
    mov     rdx, rsi
    sub     rdx, file_buffer   ; len

    ; send JSON
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, http_200_json
    mov     rdx, len_200_json
    syscall

    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, file_buffer
    ; rdx already set
    syscall

    pop     rsi
    jmp     .close_and_exit

.route_dynadd_skip:
    pop     rsi


    ; --- Simple routing: /hello returns dynamic HTML (checked before static path parsing) ---
    push    rsi
    mov     rbx, rsi
    cmp     byte [rbx], '/'
    jne     .route_skip_hello
    cmp     byte [rbx+1], 'h'
    jne     .route_skip_hello
    cmp     byte [rbx+2], 'e'
    jne     .route_skip_hello
    cmp     byte [rbx+3], 'l'
    jne     .route_skip_hello
    cmp     byte [rbx+4], 'l'
    jne     .route_skip_hello
    cmp     byte [rbx+5], 'o'
    jne     .route_skip_hello
    mov     al, byte [rbx+6]
    cmp     al, ' '
    je      .route_send_hello
    cmp     al, '?'
    jne     .route_skip_hello
.route_send_hello:
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, http_200
    mov     rdx, len_200
    syscall

    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, hello_body
    mov     rdx, len_hello_body
    syscall

    pop     rsi
    jmp     .close_and_exit
.route_skip_hello:
    pop     rsi

   

    lea     rdi, [path_buffer]
    call    parse_path_get
    lea     rdi, [path_buffer] ; RDI now holds the full, safe path to open
    jmp     .serve_file

.serve_file:
    mov     rax, SYSCALL_OPEN
    mov     rsi, O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      .handle_404
    mov     r14, rax ; Save file_fd
    mov     rax, SYSCALL_READ
    mov     rdi, r14
    mov     rsi, file_buffer
    mov     rdx, 8192
    syscall
    mov     r15, rax ; Save file length
    mov     rax, SYSCALL_CLOSE
    mov     rdi, r14
    syscall
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, http_200
    mov     rdx, len_200
    syscall
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    mov     rsi, file_buffer
    mov     rdx, r15
    syscall
    jmp     .close_and_exit

.handle_post:
    ; parse target path after "POST "
    lea     rsi, [request_buffer + 5]
    lea     rdi, [path_buffer]
    call    parse_path_write
    jc      .handle_400

    ; find body
    call    _ensure_body_loaded
    jc      .handle_400
    mov     r8, rsi
    mov     r9, rdx


    ; open/create file at resolved path
    mov     rax, SYSCALL_OPEN
    lea     rdi, [path_buffer]
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0644o
    syscall
    cmp     rax, 0
    jl      .handle_400

    mov     r14, rax
    ; write body
    mov     rax, SYSCALL_WRITE
    mov     rdi, r14
    mov     rsi, r8
    mov     rdx, r9
    syscall

    ; close file
    mov     rax, SYSCALL_CLOSE
    mov     rdi, r14
    syscall

    ; respond 201
    mov     rsi, http_201
    mov     rdx, len_201
    jmp     .send_response


.handle_put:
    lea     rsi, [request_buffer + 4] ; Path starts after "PUT "
    lea     rdi, [path_buffer]
    call    parse_path_write
    jc      .handle_400
    call    _ensure_body_loaded
    jc      .handle_400
    mov     r8, rsi
    mov     r9, rdx


    mov     rax, SYSCALL_OPEN
    lea     rdi, [path_buffer]
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0644o
    syscall
    cmp     rax, 0
    jl      .handle_400

    mov     r14, rax
    mov     rax, SYSCALL_WRITE
    mov     rdi, r14
    mov     rsi, r8
    mov     rdx, r9
    syscall

    mov     rax, SYSCALL_CLOSE
    mov     rdi, r14
    syscall

    mov     rsi, http_200
    mov     rdx, len_200
    jmp     .send_response


.handle_delete:
    lea     rsi, [request_buffer + 7] ; Path starts after "DELETE "
    lea     rdi, [path_buffer]
    call    parse_path_write
    jc      .handle_400 ; If carry is set, path was unsafe
    mov     rax, SYSCALL_UNLINK
    lea     rdi, [path_buffer]
    syscall
    cmp     rax, 0
    jl      .handle_404
    mov     rsi, http_200_del
    mov     rdx, len_200_del
    jmp     .send_response

.handle_400:
    mov     rsi, http_400
    mov     rdx, len_400
    jmp     .send_response
.handle_404:
    mov     rsi, http_404
    mov     rdx, len_404
    jmp     .send_response
.handle_405:
    mov     rsi, http_405
    mov     rdx, len_405
    jmp     .send_response

.send_response:
    mov     rax, SYSCALL_WRITE
    mov     rdi, r13
    syscall

.close_and_exit:
    mov     rax, SYSCALL_CLOSE
    mov     rdi, r13
    syscall
    mov     rax, SYSCALL_EXIT
    xor     rdi, rdi
    syscall

; Find header value by key (simple ASCII match)
; IN: rsi=request_buffer, r15=request_len, rdi=key(zero-terminated)
; OUT: rsi=ptr just after key, CF=0 if found; CF=1 if not found
find_header_value:
    push rbx
    xor rcx, rcx
.fhv_nextline:
    cmp rcx, r15
    jae .fhv_fail
    mov rbx, rdi
    xor r8, r8
.fhv_cmp_loop:
    mov al, byte [rbx]
    cmp al, 0
    je .fhv_key_end
    cmp al, byte [request_buffer+rcx+r8]
    jne .fhv_skipline
    inc rbx
    inc r8
    jmp .fhv_cmp_loop
.fhv_key_end:
    lea rsi, [request_buffer+rcx+r8]
    clc
    pop rbx
    ret
.fhv_skipline:
    inc rcx
    cmp byte [request_buffer+rcx], 10
    jne .fhv_skipline
    inc rcx
    jmp .fhv_nextline
.fhv_fail:
    stc
    pop rbx
    ret

; parse unsigned int at RSI, stop on non-digit; OUT: RAX=value, RSI advanced
parse_int:
    xor rax, rax
.pi_loop:
    mov bl, byte [rsi]
    cmp bl, '0'
    jb .pi_end
    cmp bl, '9'
    ja .pi_end
    imul rax, rax, 10
    sub bl, '0'
    add rax, rbx
    inc rsi
    jmp .pi_loop
.pi_end:
    ret

; write RBX as decimal at RSI, advance RSI
u32_to_dec:
    push rax
    push rcx
    push rdx
    push rdi
    mov  rdi, rsi
    mov  rcx, 0
.ud_divloop:
    xor  rdx, rdx
    mov  rax, rbx
    mov  r8, 10
    div  r8
    add  dl, '0'
    push rdx
    inc  rcx
    mov  rbx, rax
    test rbx, rbx
    jnz  .ud_divloop
.ud_out:
    pop  rdx
    mov  byte [rdi], dl
    inc  rdi
    loop .ud_out
    mov  rsi, rdi
    pop  rdi
    pop  rdx
    pop  rcx
    pop  rax
    ret



parse_path_get:
    ; Parses path for GET. If path is '/', sets buffer to 'www/index.html'.
    ; If path starts with '/', skip it before building full path.
    cmp     byte [rsi], '/'
    jne     .not_root
    cmp     byte [rsi+1], ' '
    je      .path_is_root
    inc     rsi
.not_root:
    call    build_full_path
    jc      .path_is_root ; If unsafe, also serve root as a safe default
    ret
.path_is_root:
    mov     rdi, path_buffer
    mov     rsi, file_root
.copy_root_path:
    movsb
    cmp     byte [rsi-1], 0
    jne     .copy_root_path
    ret

parse_path_write:
    ; Parses path for PUT/DELETE. Returns carry flag if unsafe.
    cmp     byte [rsi], '/'
    jne     .pw_build
    inc     rsi                 ; skip leading '/'
.pw_build:
    call    build_full_path
    ret

build_full_path:
    ; Input:  rsi = raw path after method (possibly starting at '/')
    ;         rdi = path_buffer
    ; Output: path_buffer = "www/<path>\0"
    ;         CF=1 if unsafe, CF=0 if safe

    push    rsi                         ; keep original
    mov     rdi, path_buffer
    mov     rsi, www_prefix
    mov     rcx, len_www_prefix
    rep     movsb                       ; "www/"
    pop     rsi

    ; copy path chars until space
.parse_loop:
    mov     al, [rsi]
    cmp     al, ' '
    je      .found_end
    mov     [rdi], al
    inc     rsi
    inc     rdi
    jmp     .parse_loop

.found_end:
    mov     byte [rdi], 0               ; NUL-terminate

    ; First try the C helper (bonus feature)
    lea     rdi, [path_buffer]
    call    is_path_safe
    test    rax, rax
    jne     .path_safe                  ; C says OK → accept

    ; Assembly fallback: allow [A-Za-z0-9._-] only, require at least one '.',
    ; and no extra '/' after "www/"
    lea     rsi, [path_buffer + len_www_prefix]
    xor     ecx, ecx                    ; seen_dot = 0
.fb_loop:
    mov     al, [rsi]
    test    al, al
    je      .fb_done                    ; end of string
    cmp     al, '/'
    je      .fb_unsafe
    cmp     al, '.'
    jne     .fb_notdot
    inc     ecx
.fb_notdot:
    ; 0..9
    cmp     al, '0'
    jb      .fb_more
    cmp     al, '9'
    jbe     .fb_ok

.fb_more:
    ; A..Z
    cmp     al, 'A'
    jb      .fb_lower
    cmp     al, 'Z'
    jbe     .fb_ok

.fb_lower:
    ; a..z
    cmp     al, 'a'
    jb      .fb_sym
    cmp     al, 'z'
    jbe     .fb_ok

.fb_sym:
    cmp     al, '_'
    je      .fb_ok
    cmp     al, '-'
    je      .fb_ok
    cmp     al, '.'
    je      .fb_ok
    jmp     .fb_unsafe

.fb_ok:
    inc     rsi
    jmp     .fb_loop

.fb_done:
    test    ecx, ecx
    jz      .fb_unsafe                  ; must contain dot in filename
.path_safe:
    clc
    ret

.fb_unsafe:
    stc
    ret


find_body:
    ; Finds the start of the HTTP body by scanning for CRLFCRLF ("").
    ; Input: r15 = request length
    ; Output: rsi = pointer to body, rdx = body length, CF=0 on success, CF=1 on error
    xor     rcx, rcx
.fb_loop:
    cmp     rcx, r15
    jae     .fb_error
    mov     al, byte [request_buffer + rcx]
    cmp     al, 13
    jne     .fb_next
    cmp     byte [request_buffer + rcx + 1], 10
    jne     .fb_next
    cmp     byte [request_buffer + rcx + 2], 13
    jne     .fb_next
    cmp     byte [request_buffer + rcx + 3], 10
    jne     .fb_next
    lea     rsi, [request_buffer + rcx + 4]
    mov     rdx, r15
    sub     rdx, rcx
    sub     rdx, 4
    clc
    ret
.fb_next:
    inc     rcx
    jmp     .fb_loop

.fb_error:
    xor     rcx, rcx
.fb2_loop:
    cmp     rcx, r15
    jae     .fb_fail
    cmp     byte [request_buffer + rcx], 10
    jne     .fb2_next
    cmp     byte [request_buffer + rcx + 1], 10
    jne     .fb2_next
    lea     rsi, [request_buffer + rcx + 2]
    mov     rdx, r15
    sub     rdx, rcx
    sub     rdx, 2
    clc
    ret
.fb2_next:
    inc     rcx
    jmp     .fb2_loop

.fb_fail:
    stc
    ret

.found_body:
    lea     rsi, [request_buffer + rcx + 4] ; Body starts after the separator
    mov     rdx, r15
    sub     rdx, rcx
    sub     rdx, 4 ; rdx is now the length of the body
    clc ; Clear carry flag to indicate success
    ret

_ensure_body_loaded:
    push rbx
    ; Try with what we have
    call    find_body
    jnc     .check_len
    ; If not found, read more a few times
    xor     rbx, rbx
.el_try_again:
    mov     rax, 2048
    sub     rax, r15
    cmp     rax, 0
    je      .fail
    mov     rax, SYSCALL_READ
    mov     rdi, r13
    lea     rsi, [request_buffer + r15]
    mov     rdx, 2048
    sub     rdx, r15
    syscall
    cmp     rax, 0
    jle     .fail
    add     r15, rax
    call    find_body
    jnc     .check_len
    inc     rbx
    cmp     rbx, 8
    jl      .el_try_again
    jmp     .fail

.check_len:
    push    rsi
    push    rdx
    lea     rdi, [rel clen_key]
    lea     rsi, [request_buffer]
    call    find_header_value
    jc      .done_len
    call    parse_int
    mov     r10, rax
    pop     rdx
    pop     rsi
.more_body:
    cmp     rdx, r10
    jae     .done_len
    mov     rax, 2048
    sub     rax, r15
    cmp     rax, 0
    je      .fail
    mov     rax, SYSCALL_READ
    mov     rdi, r13
    lea     rsi, [request_buffer + r15]
    mov     rdx, 2048
    sub     rdx, r15
    syscall
    cmp     rax, 0
    jle     .fail
    add     r15, rax
    call    find_body
    jc      .fail
    jmp     .more_body

.done_len:
    clc
    pop     rbx
    ret
.fail:
    stc
    pop     rbx
    ret
