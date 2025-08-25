; =============================================================================
; asmhttpd: A simple, robust HTTP server in x86-64 Assembly for Linux (NASM)
; Final version with all bug fixes.
; =============================================================================

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

; Simple dynamic HTML body for /hello
hello_body      db '<!doctype html><html><body><h1>Why is this shit harder than I thought HOLY SHIEET!!</h1></body></html>'
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
    call    find_body
    jc      .handle_400 ; Jump if carry is set (body not found)
    mov     rax, SYSCALL_OPEN
    mov     rdi, post_filename
    mov     rsi, O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0644o
    syscall
    mov     r14, rax ; file_fd
    mov     rax, SYSCALL_WRITE
    mov     rdi, r14
    ; rsi (body pointer) and rdx (body length) are already set by find_body
    syscall
    mov     rax, SYSCALL_CLOSE
    mov     rdi, r14
    syscall
    mov     rsi, http_201
    mov     rdx, len_201
    jmp     .send_response

.handle_put:
    lea     rsi, [request_buffer + 4] ; Path starts after "PUT "
    lea     rdi, [path_buffer]
    call    parse_path_write
    jc      .handle_400 ; If carry is set, path was unsafe
    call    find_body
    jc      .handle_400
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
    ; rsi (body pointer) and rdx (body length) are already set by find_body
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

; --- Helper Subroutines ---
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
    call build_full_path
    ret

build_full_path:
    ; Input: rsi=path from request, rdi=path_buffer.
    ; Output: rdi has full path. CF is set if path is unsafe.
    push    rsi ; Save original path pointer
    mov     rdi, path_buffer
    mov     rsi, www_prefix
    mov     rcx, len_www_prefix
    rep movsb   ; Copy "www/" into buffer
    pop     rsi ; Restore original path pointer
.parse_loop:
    mov     al, byte [rsi]
    cmp     al, ' '
    je      .found_end
    mov     byte [rdi], al
    inc     rsi
    inc     rdi
    jmp     .parse_loop
.found_end:
    mov     byte [rdi], 0 ; Null-terminate
    ; [BONUS] Call C function for security check
    lea     rdi, [path_buffer]
    call    is_path_safe
    cmp     rax, 0
    jne     .path_safe
    ; Path is unsafe, set carry flag and return
    stc
    ret
.path_safe:
    ; Path is safe, clear carry flag and return
    clc
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