; =============================================================================
; asmhttpd: A simple HTTP server in x86-64 Assembly for Linux
;
; Features:
; - Listens on a specified port (-p)
; - Serves files from a document root (-d)
; - Forks a new process for each request
; - Handles GET, POST, PUT, DELETE methods
; - Simple routing for /hello and /auth
; - Basic Authentication for /auth
; - Integration with a C plugin for dynamic routes (/dyn/*)
; =============================================================================

%define SYSCALL_READ        0
%define SYSCALL_WRITE       1
%define SYSCALL_OPEN        2
%define SYSCALL_CLOSE       3
%define SYSCALL_STAT        4
%define SYSCALL_FSTAT       5
%define SYSCALL_LSEEK       8
%define SYSCALL_MMAP        9
%define SYSCALL_EXIT        60
%define SYSCALL_FORK        57
%define SYSCALL_SOCKET      41
%define SYSCALL_BIND        49
%define SYSCALL_LISTEN      50
%define SYSCALL_ACCEPT      43
%define SYSCALL_SENDFile    40
%define SYSCALL_SETSOCKOPT  54

%define AF_INET     2
%define SOCK_STREAM 1
%define PROTO_TCP   6

%define SOL_SOCKET  1
%define SO_REUSEADDR 2

%define O_RDONLY    0

%define STDIN       0
%define STDOUT      1
%define STDERR      2

%define BUF_SIZE    4096

; =============================================================================
;    DATA SECTION (Initialized Data)
; =============================================================================
section .data
    ; --- Command Line Argument Strings ---
    p_opt           db "-p", 0
    d_opt           db "-d", 0

    ; --- Server Messages ---
    listen_msg_1    db "Server listening on http://127.0.0.1:", 0
    listen_msg_2    db " with docroot '", 0
    listen_msg_3    db "'...", 10, 0
    usage_msg       db "Usage: ./asmhttpd -p <port> -d <docroot>", 10, 0
    err_socket      db "Error: socket() failed", 10, 0
    err_bind        db "Error: bind() failed", 10, 0
    err_listen      db "Error: listen() failed", 10, 0
    err_fork        db "Error: fork() failed", 10, 0
    err_docroot     db "Error: Invalid document root", 10, 0

    ; --- HTTP Responses ---
    http_200_ok     db "HTTP/1.1 200 OK", 13, 10, 0
    http_400_bad    db "HTTP/1.1 400 Bad Request", 13, 10, "Content-Type: text/plain", 13, 10, "Content-Length: 12", 13, 10, 13, 10, "Bad Request", 13, 10, 0
    http_401_auth   db "HTTP/1.1 401 Unauthorized", 13, 10, "WWW-Authenticate: Basic realm=""User Visible Realm""", 13, 10, "Content-Length: 13", 13, 10, 13, 10, "Unauthorized", 13, 10, 0
    http_404_notf   db "HTTP/1.1 404 Not Found", 13, 10, "Content-Type: text/plain", 13, 10, "Content-Length: 10", 13, 10, 13, 10, "Not Found", 13, 10, 0
    http_500_err    db "HTTP/1.1 500 Internal Server Error", 13, 10, "Content-Type: text/plain", 13, 10, "Content-Length: 22", 13, 10, 13, 10, "Internal Server Error", 13, 10, 0

    ; --- HTTP Headers ---
    hdr_len_pfx     db "Content-Length: ", 0
    hdr_len_sfx     db 13, 10, 13, 10, 0
    hdr_ct_html     db "Content-Type: text/html", 13, 10, 0
    hdr_ct_css      db "Content-Type: text/css", 13, 10, 0
    hdr_ct_js       db "Content-Type: application/javascript", 13, 10, 0
    hdr_ct_png      db "Content-Type: image/png", 13, 10, 0
    hdr_ct_jpg      db "Content-Type: image/jpeg", 13, 10, 0
    hdr_ct_gif      db "Content-Type: image/gif", 13, 10, 0
    hdr_ct_plain    db "Content-Type: text/plain", 13, 10, 0
    hdr_conn_close  db "Connection: close", 13, 10, 0

    ; --- Hardcoded Routes ---
    path_hello      db "/hello", 0
    resp_hello      db "Hello from Assembly!", 10, 0
    path_auth       db "/auth", 0
    resp_auth_ok    db "Authenticated!", 10, 0
    auth_header_pfx db "Authorization: Basic ", 0
    auth_token      db "YWRtaW46c2VjcmV0", 0 ; "admin:secret" in base64
    path_dyn_pfx    db "/dyn/", 0

; =============================================================================
;    BSS SECTION (Uninitialized Data)
; =============================================================================
section .bss
    port            resq 1
    docroot_ptr     resq 1
    docroot_len     resq 1
    listen_fd       resq 1

    ; Buffers for each child process (on its stack)
    ; We define their sizes here for clarity.
    %define REQ_BUF_SIZE     4096
    %define PATH_BUF_SIZE    1024
    %define HDR_BUF_SIZE     256
    %define FILEPATH_SIZE    2048
    %define DYN_OUT_BUF_SIZE 2048
    %define STAT_BUF_SIZE    144

; =============================================================================
;    TEXT SECTION (Code)
; =============================================================================
section .text
global _start

; Declare external C function from plugin.o
extern plugin_dispatch

; --- Helper Functions ---

; write_str: Writes a null-terminated string to a file descriptor.
; rdi: file descriptor
; rsi: pointer to string
write_str:
    push rdi          ; Save fd
    push rsi          ; Save string pointer
    call strlen       ; rax = length of string
    pop rsi           ; Restore string pointer
    pop rdi           ; Restore fd
    mov rdx, rax      ; rdx = length
    mov rax, SYSCALL_WRITE
    syscall
    ret

; strlen: Calculates the length of a null-terminated string.
; rdi: pointer to string
; Returns: rax = length
strlen:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .end
    inc rax
    jmp .loop
.end:
    ret

; atoi: Converts a string to an integer.
; rdi: pointer to string
; Returns: rax = integer value
atoi:
    xor rax, rax
    xor rcx, rcx
.loop:
    movzx rdx, byte [rdi + rcx]
    cmp rdx, '0'
    jb .done
    cmp rdx, '9'
    ja .done
    sub rdx, '0'
    imul rax, 10
    add rax, rdx
    inc rcx
    jmp .loop
.done:
    ret

; itoa: Converts an integer to a string.
; rdi: integer value
; rsi: buffer to write string into
itoa:
    mov rcx, rsi    ; Save buffer pointer
    mov rbx, 10     ; Divisor
    xor rdx, rdx
.loop:
    div rbx         ; rax = rax / 10, rdx = rax % 10
    add rdx, '0'    ; Convert digit to ASCII
    push rdx        ; Push onto stack
    test rax, rax
    jnz .loop
.write:
    pop rax         ; Pop digit
    mov [rcx], al   ; Write to buffer
    inc rcx
    cmp rcx, rsp    ; Check if stack is empty
    jbe .write
    mov byte [rcx], 0 ; Null-terminate
    ret

; strcmp: Compares two strings.
; rdi: string 1
; rsi: string 2
; Returns: rax = 0 if equal, non-zero otherwise
strcmp:
.loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .notequal
    cmp al, 0
    je .equal
    inc rdi
    inc rsi
    jmp .loop
.notequal:
    sub rax, rbx
    ret
.equal:
    xor rax, rax
    ret

; strncmp: Compares first n bytes of two strings.
; rdi: string 1
; rsi: string 2
; rdx: n
; Returns: rax = 0 if equal
strncmp:
    xor rax, rax
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    je .equal
    mov al, [rdi + rcx]
    mov bl, [rsi + rcx]
    cmp al, bl
    jne .notequal
    cmp al, 0
    je .equal
    inc rcx
    jmp .loop
.notequal:
    sub rax, rbx
    ret
.equal:
    xor rax, rax
    ret

; find_char: Finds first occurrence of a character in a string.
; rdi: string
; rsi: char
; Returns: rax = pointer to char, or 0 if not found
find_char:
    mov al, sil
.loop:
    cmp byte [rdi], al
    je .found
    cmp byte [rdi], 0
    je .notfound
    inc rdi
    jmp .loop
.found:
    mov rax, rdi
    ret
.notfound:
    xor rax, rax
    ret

; log_line: Logs a request line like "GET /path"
; rdi: method string
; rsi: path string
log_line:
    push rdi
    push rsi

    ; Print method
    mov rdi, STDOUT
    pop rsi
    call write_str

    ; Print space
    mov rdi, STDOUT
    mov rsi, ' '
    push rsi
    mov rsi, rsp
    mov rdx, 1
    mov rax, SYSCALL_WRITE
    syscall
    pop rsi

    ; Print path
    mov rdi, STDOUT
    pop rsi
    call write_str

    ; Print newline
    mov rdi, STDOUT
    mov rsi, 10
    push rsi
    mov rsi, rsp
    mov rdx, 1
    mov rax, SYSCALL_WRITE
    syscall
    pop rsi

    ret

; --- Main Program Logic ---
_start:
    ; --- Argument Parsing ---
    pop rcx             ; argc
    mov r12, rcx        ; Save argc
    mov r13, rsp        ; Save argv
    cmp rcx, 5
    jne .usage          ; Must be ./asmhttpd -p <port> -d <docroot>

    mov rdi, [rsp + 8]  ; argv[1]
    mov rsi, p_opt
    call strcmp
    test rax, rax
    jnz .usage          ; Must be -p

    mov rdi, [rsp + 16] ; argv[2]
    call atoi
    mov [port], rax

    mov rdi, [rsp + 24] ; argv[3]
    mov rsi, d_opt
    call strcmp
    test rax, rax
    jnz .usage

    mov rax, [rsp + 32] ; argv[4]
    mov [docroot_ptr], rax
    mov rdi, rax
    call strlen
    mov [docroot_len], rax
    cmp rax, 0
    je .docroot_error

    jmp .setup_server

.usage:
    mov rdi, STDERR
    mov rsi, usage_msg
    call write_str
    jmp .exit_error

.docroot_error:
    mov rdi, STDERR
    mov rsi, err_docroot
    call write_str
    jmp .exit_error

.setup_server:
    ; --- Create Socket ---
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    mov rdx, PROTO_TCP
    mov rax, SYSCALL_SOCKET
    syscall
    cmp rax, 0
    jl .socket_fail
    mov [listen_fd], rax

    ; --- Set SO_REUSEADDR ---
    mov rdi, [listen_fd]
    mov rsi, SOL_SOCKET
    mov rdx, SO_REUSEADDR
    mov r10, 1          ; True
    push r10
    mov r10, rsp
    mov r8, 4           ; sizeof(int)
    mov rax, SYSCALL_SETSOCKOPT
    syscall
    pop r10

    ; --- Bind Socket ---
    sub rsp, 16                 ; Allocate sockaddr_in struct
    mov rdi, [listen_fd]
    mov rsi, rsp
    mov rdx, 16                 ; sizeof(sockaddr_in)
    mov word [rsi], AF_INET     ; sin_family
    mov rax, [port]
    bswap ax                    ; Host to network byte order (htons)
    mov word [rsi + 2], ax      ; sin_port
    mov dword [rsi + 4], 0      ; sin_addr (INADDR_ANY)
    mov rax, SYSCALL_BIND
    syscall
    add rsp, 16                 ; Deallocate
    test rax, rax
    jl .bind_fail

    ; --- Listen ---
    mov rdi, [listen_fd]
    mov rsi, 20                 ; Backlog
    mov rax, SYSCALL_LISTEN
    syscall
    test rax, rax
    jl .listen_fail

    ; --- Print Listening Message ---
    mov rdi, STDOUT
    mov rsi, listen_msg_1
    call write_str
    mov rdi, [port]
    lea rsi, [rsp - 20]
    call itoa
    mov rdi, STDOUT
    lea rsi, [rsp - 20]
    call write_str
    mov rdi, STDOUT
    mov rsi, listen_msg_2
    call write_str
    mov rdi, STDOUT
    mov rsi, [docroot_ptr]
    call write_str
    mov rdi, STDOUT
    mov rsi, listen_msg_3
    call write_str

.accept_loop:
    ; --- Accept Connection ---
    mov rdi, [listen_fd]
    xor rsi, rsi
    xor rdx, rdx
    mov rax, SYSCALL_ACCEPT
    syscall
    cmp rax, 0
    jl .accept_loop ; Silently ignore accept errors and continue

    mov r14, rax    ; Save client_fd

    ; --- Fork Process ---
    mov rax, SYSCALL_FORK
    syscall
    cmp rax, 0
    jl .fork_fail
    je .child_process   ; If rax == 0, we are in the child

.parent_process:
    ; Close the client socket in the parent and loop back
    mov rdi, r14
    mov rax, SYSCALL_CLOSE
    syscall
    jmp .accept_loop

.child_process:
    ; Close the listening socket in the child
    mov rdi, [listen_fd]
    mov rax, SYSCALL_CLOSE
    syscall

    call handle_client  ; r14 still holds client_fd

    ; Close client socket and exit
    mov rdi, r14
    mov rax, SYSCALL_CLOSE
    syscall
    jmp .exit_ok

.socket_fail:
    mov rdi, STDERR
    mov rsi, err_socket
    call write_str
    jmp .exit_error

.bind_fail:
    mov rdi, STDERR
    mov rsi, err_bind
    call write_str
    jmp .exit_error

.listen_fail:
    mov rdi, STDERR
    mov rsi, err_listen
    call write_str
    jmp .exit_error

.fork_fail:
    mov rdi, STDERR
    mov rsi, err_fork
    call write_str
    ; Close the accepted socket before exiting
    mov rdi, r14
    mov rax, SYSCALL_CLOSE
    syscall
    jmp .exit_error

.exit_ok:
    mov rax, SYSCALL_EXIT
    mov rdi, 0
    syscall

.exit_error:
    mov rax, SYSCALL_EXIT
    mov rdi, 1
    syscall

; =============================================================================
; handle_client: Main request handling logic for the child process.
; Assumes client_fd is in r14.
; =============================================================================
handle_client:
    sub rsp, REQ_BUF_SIZE + PATH_BUF_SIZE + HDR_BUF_SIZE + FILEPATH_SIZE + DYN_OUT_BUF_SIZE + STAT_BUF_SIZE ; Allocate stack space for buffers
    lea r15, [rsp] ; req_buf
    lea r12, [r15 + REQ_BUF_SIZE] ; path_buf
    lea r11, [r12 + PATH_BUF_SIZE] ; hdr_buf
    lea r10, [r11 + HDR_BUF_SIZE] ; filepath_buf
    lea r9,  [r10 + FILEPATH_SIZE] ; dyn_out_buf
    lea r8,  [r9 + DYN_OUT_BUF_SIZE] ; stat_buf

    ; --- Read Request ---
    mov rdi, r14        ; client_fd
    mov rsi, r15        ; req_buf
    mov rdx, REQ_BUF_SIZE - 1
    mov rax, SYSCALL_READ
    syscall
    cmp rax, 0
    jle .end_handle     ; Read failed or empty request

    mov byte [r15 + rax], 0 ; Null-terminate request

    ; --- Parse Request Line ---
    ; Find method (e.g., "GET")
    mov rdi, r15
    mov rsi, ' '
    call find_char
    cmp rax, 0
    je .bad_request
    mov byte [rax], 0   ; Terminate method string
    mov rbx, r15        ; rbx = method

    ; Find path
    inc rax
    mov rdi, rax
    mov rsi, ' '
    call find_char
    cmp rax, 0
    je .bad_request
    mov byte [rax], 0   ; Terminate path string
    mov rcx, rdi        ; rcx = path

    ; Log the request
    mov rdi, rbx
    mov rsi, rcx
    call log_line

    ; --- Routing ---
    ; Check method and path to decide action
    mov rdi, rbx
    mov rsi, "GET"
    call strcmp
    test rax, rax
    jnz .handle_post_put_delete ; If not GET, handle others

.handle_get:
    ; Simple routing for GET requests
    mov rdi, rcx        ; path
    mov rsi, path_hello
    call strcmp
    test rax, rax
    je .get_hello

    mov rdi, rcx
    mov rsi, path_auth
    call strcmp
    test rax, rax
    je .get_auth

    mov rdi, rcx
    mov rsi, path_dyn_pfx
    mov rdx, 5 ; strlen("/dyn/")
    call strncmp
    test rax, rax
    je .get_dyn

    ; Default to serving a static file
    jmp .serve_static_file

.get_hello:
    ; Handle /hello
    mov rdi, r14
    mov rsi, http_200_ok
    call write_str
    mov rdi, r14
    mov rsi, hdr_ct_plain
    call write_str
    mov rdi, r14
    mov rsi, hdr_conn_close
    call write_str
    mov rdi, resp_hello
    call strlen
    mov rbx, rax ; save length
    ; build "Content-Length: xx\r\n\r\n"
    mov rdi, r14
    mov rsi, hdr_len_pfx
    call write_str
    mov rdi, rbx
    mov rsi, r11 ; hdr_buf
    call itoa
    mov rdi, r14
    mov rsi, r11
    call write_str
    mov rdi, r14
    mov rsi, hdr_len_sfx
    call write_str
    ; send body
    mov rdi, r14
    mov rsi, resp_hello
    mov rdx, rbx
    mov rax, SYSCALL_WRITE
    syscall
    jmp .end_handle

.get_auth:
    ; Handle /auth - check for Authorization header
    mov rdi, r15 ; request buffer
    mov rsi, auth_header_pfx
    call strstr_simple
    cmp rax, 0
    je .auth_fail ; Header not found

    add rax, 21 ; strlen("Authorization: Basic ")
    mov rdi, rax
    mov rsi, auth_token
    mov rdx, 20 ; strlen("YWRtaW46c2VjcmV0")
    call strncmp
    test rax, rax
    jne .auth_fail

.auth_ok:
    ; Send authenticated response
    mov rdi, r14
    mov rsi, http_200_ok
    call write_str
    mov rdi, r14
    mov rsi, hdr_ct_plain
    call write_str
    mov rdi, r14
    mov rsi, hdr_conn_close
    call write_str
    mov rdi, resp_auth_ok
    call strlen
    mov rbx, rax
    ; build Content-Length header
    mov rdi, r14
    mov rsi, hdr_len_pfx
    call write_str
    mov rdi, rbx
    mov rsi, r11 ; hdr_buf
    call itoa
    mov rdi, r14
    mov rsi, r11
    call write_str
    mov rdi, r14
    mov rsi, hdr_len_sfx
    call write_str
    ; send body
    mov rdi, r14
    mov rsi, resp_auth_ok
    mov rdx, rbx
    mov rax, SYSCALL_WRITE
    syscall
    jmp .end_handle

.auth_fail:
    ; Send 401 Unauthorized
    mov rdi, r14
    mov rsi, http_401_auth
    call write_str
    jmp .end_handle

.get_dyn:
    ; Handle /dyn/* by calling C plugin
    ; extern int plugin_dispatch(
    ;   const char* method,   ; RDI
    ;   const char* path,     ; RSI
    ;   const char* query,    ; RDX
    ;   const char* body,     ; RCX
    ;   int   body_len,       ; R8
    ;   char* out,            ; R9
    ;   int   out_cap,        ; on stack
    ;   int* out_status,     ; on stack
    ;   const char** out_ct); ; on stack

    ; Find query string
    mov rdi, rcx ; path
    mov rsi, '?'
    call find_char
    mov r13, 0   ; query_ptr
    cmp rax, 0
    je .no_query
    mov byte [rax], 0 ; split path and query
    inc rax
    mov r13, rax ; query_ptr = start of query string
.no_query:

    sub rsp, 24 ; space for stack args
    mov qword [rsp + 16], 0 ; out_ct ptr
    lea rax, [rsp + 16]
    push rax
    mov dword [rsp + 8], 0 ; out_status
    lea rax, [rsp + 8]
    push rax
    push DYN_OUT_BUF_SIZE ; out_cap
    
    mov rdi, "GET"
    mov rsi, rcx
    mov rdx, r13
    xor rcx, rcx ; no body
    xor r8, r8   ; no body_len
    mov r9, r9   ; dyn_out_buf
    call plugin_dispatch
    mov rbx, rax ; save returned length

    ; Pop stack arguments
    add rsp, 40

    ; Get status and content-type from plugin
    mov rsi, [rsp + 16] ; out_ct
    mov edi, [rsp + 8] ; out_status

    ; Respond with plugin's output
    cmp edi, 200
    jne .dyn_not_ok
    mov rdi, r14
    mov r10, rsi ; save out_ct
    mov rsi, http_200_ok
    call write_str
    mov rdi, r14
    mov rsi, r10 ; restore out_ct
    call write_str
    jmp .dyn_send_body

.dyn_not_ok:
    ; Assume 404 for now
    mov rdi, r14
    mov rsi, http_404_notf
    call write_str

.dyn_send_body:
    mov rdi, r14
    mov rsi, hdr_conn_close
    call write_str
    ; build Content-Length
    mov rdi, r14
    mov rsi, hdr_len_pfx
    call write_str
    mov rdi, rbx
    mov rsi, r11 ; hdr_buf
    call itoa
    mov rdi, r14
    mov rsi, r11
    call write_str
    mov rdi, r14
    mov rsi, hdr_len_sfx
    call write_str
    ; send body
    mov rdi, r14
    mov rsi, r9 ; dyn_out_buf
    mov rdx, rbx
    mov rax, SYSCALL_WRITE
    syscall
    jmp .end_handle

.serve_static_file:
    ; Build file path: docroot + requested path
    mov rdi, r10 ; filepath_buf
    mov rsi, [docroot_ptr]
    call strcpy
    mov rdi, r10
    add rdi, [docroot_len]
    mov rsi, rcx ; requested path
    call strcpy

    ; Check for directory traversal
    mov rdi, rcx
    mov rsi, ".."
    call strstr_simple
    test rax, rax
    jnz .bad_request

    ; If path is "/", append "index.html"
    mov rdi, rcx
    mov rsi, "/"
    call strcmp
    test rax, rax
    jne .open_file
    mov rdi, r10
    add rdi, [docroot_len]
    mov rsi, "/index.html"
    call strcpy

.open_file:
    mov rdi, r10 ; filepath
    mov rsi, O_RDONLY
    xor rdx, rdx
    mov rax, SYSCALL_OPEN
    syscall
    cmp rax, 0
    jl .not_found
    mov r13, rax ; file_fd

    ; Get file size using fstat
    mov rdi, r13
    mov rsi, r8 ; stat_buf
    mov rax, SYSCALL_FSTAT
    syscall
    test rax, rax
    jl .internal_error

    mov rbx, [r8 + 48] ; st_size is at offset 48 in stat struct

    ; Send headers
    mov rdi, r14
    mov rsi, http_200_ok
    call write_str
    ; TODO: Determine Content-Type from file extension
    mov rdi, r14
    mov rsi, hdr_ct_html ; Defaulting to html for now
    call write_str
    mov rdi, r14
    mov rsi, hdr_conn_close
    call write_str
    ; Send Content-Length
    mov rdi, r14
    mov rsi, hdr_len_pfx
    call write_str
    mov rdi, rbx
    mov rsi, r11 ; hdr_buf
    call itoa
    mov rdi, r14
    mov rsi, r11
    call write_str
    mov rdi, r14
    mov rsi, hdr_len_sfx
    call write_str

    ; Send file content using sendfile
    mov rdi, r14        ; out_fd
    mov rsi, r13        ; in_fd
    xor rdx, rdx        ; offset
    mov r10, rbx        ; count
    mov rax, SYSCALL_SENDFile
    syscall

    ; Close file
    mov rdi, r13
    mov rax, SYSCALL_CLOSE
    syscall
    jmp .end_handle

.handle_post_put_delete:
    ; For POST, PUT, DELETE, we just send a 200 OK as a placeholder
    ; A real implementation would handle file uploads or deletions.
    mov rdi, r14
    mov rsi, http_200_ok
    call write_str
    mov rdi, r14
    mov rsi, hdr_conn_close
    call write_str
    mov rdi, r14
    mov rsi, hdr_len_pfx
    call write_str
    mov rdi, r14
    mov rsi, "0" ; Zero content length
    call write_str
    mov rdi, r14
    mov rsi, hdr_len_sfx
    call write_str
    jmp .end_handle

.bad_request:
    mov rdi, r14
    mov rsi, http_400_bad
    call write_str
    jmp .end_handle

.not_found:
    mov rdi, r14
    mov rsi, http_404_notf
    call write_str
    jmp .end_handle

.internal_error:
    ; Close file if open
    cmp r13, 0
    jle .send_500
    mov rdi, r13
    mov rax, SYSCALL_CLOSE
    syscall
.send_500:
    mov rdi, r14
    mov rsi, http_500_err
    call write_str
    jmp .end_handle

.end_handle:
    ; Restore stack pointer before returning
    add rsp, REQ_BUF_SIZE + PATH_BUF_SIZE + HDR_BUF_SIZE + FILEPATH_SIZE + DYN_OUT_BUF_SIZE + STAT_BUF_SIZE
    ret

; --- More String Helpers ---

; strcpy: Copies string from rsi to rdi
strcpy:
.loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    cmp al, 0
    jne .loop
    ret

; strstr_simple: Finds substring (rsi) in string (rdi)
; Returns: pointer to start of substring in rax, or 0
strstr_simple:
    push rdi
    push rsi
.outer_loop:
    mov r8, rdi
    mov r9, rsi
.inner_loop:
    mov al, [r9]
    cmp al, 0
    je .found
    mov bl, [r8]
    cmp bl, 0
    je .not_found
    cmp al, bl
    jne .next_char
    inc r8
    inc r9
    jmp .inner_loop
.next_char:
    inc rdi
    jmp .outer_loop
.found:
    mov rax, rdi
    pop rsi
    pop rdi
    ret
.not_found:
    xor rax, rax
    pop rsi
    pop rdi
    ret