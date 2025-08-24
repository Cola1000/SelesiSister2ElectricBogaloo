; server.asm — asmhttpd (x86-64 Linux, NASM, System V ABI, glibc calls)
; Build: nasm -f elf64 -g -F dwarf server.asm -o server.o
; Link : gcc -no-pie -O2 -o asmhttpd server.o plugin.o
; Run  : ./asmhttpd -p 8080 -d ./www

        default rel
        global  main

        extern  socket, bind, listen, accept, fork, read, write, close, open, lseek, exit
        extern  strlen, memcpy, strcmp, strncmp, strstr
        extern  htons
        extern  plugin_dispatch

%define AF_INET      2
%define SOCK_STREAM  1
%define INADDR_ANY   0
%define O_RDONLY     0
%define O_WRONLY     1
%define O_CREAT      64
%define O_TRUNC      512
%define SEEK_SET     0
%define SEEK_END     2

SECTION .data
usage_msg:      db 'Usage: ./asmhttpd -p PORT -d DOCROOT',13,10,0
crlf:           db 13,10,0
crlfcrlf:       db 13,10,13,10,0
hdr_200:        db 'HTTP/1.1 200 OK',13,10,0
hdr_201:        db 'HTTP/1.1 201 Created',13,10,0
hdr_401:        db 'HTTP/1.1 401 Unauthorized',13,10,'WWW-Authenticate: Basic realm="asmhttpd"',13,10,0
hdr_404:        db 'HTTP/1.1 404 Not Found',13,10,0
hdr_405:        db 'HTTP/1.1 405 Method Not Allowed',13,10,0
hdr_500:        db 'HTTP/1.1 500 Internal Server Error',13,10,0
ct_text:        db 'Content-Type: text/plain',13,10,0
ct_html:        db 'Content-Type: text/html',13,10,0
ct_json:        db 'Content-Type: application/json',13,10,0
cl_hdr:         db 'Content-Length: ',0
conn_close:     db 'Connection: close',13,10,0
server_hdr:     db 'Server: asmhttpd',13,10,0
basic_prefix:   db 'Authorization: Basic ',0
basic_good:     db 'YWRtaW46c2VjcmV0',0  ; admin:secret (base64)
idx_def:        db '/index.html',0
get_s:          db 'GET',0
post_s:         db 'POST',0
put_s:          db 'PUT',0
delete_s:       db 'DELETE',0
p_hello:        db '/hello',0
p_auth:         db '/auth',0
p_dyn:          db '/dyn',0
p_dotdot:       db '..',0
cl_key:         db 'Content-Length:',0
ext_html:       db '.html',0
arg_p:          db '-p',0
arg_d:          db '-d',0
defroot:        db './www',0

; small bodies
hello_msg:      db 'Hello from asmhttpd',13,10
hello_len:      equ $-hello_msg
auth_msg:       db 'auth required',13,10
auth_len:       equ $-auth_msg
ok_msg:         db 'ok',13,10
ok_len:         equ $-ok_msg
nf_msg:         db 'not found',13,10
nf_len:         equ $-nf_msg
sev_msg:        db 'server error',13,10
sev_len:        equ $-sev_msg
created_msg:    db 'created',13,10
created_len:    equ $-created_msg

; sockaddr_in
sin:            dw AF_INET
sin_port:       dw 0
sin_addr:       dd INADDR_ANY
sin_zero:       dq 0

SECTION .bss
reqbuf:         resb 16384
hdrbuf:         resb 8192
methodbuf:      resb 16
pathbuf:        resb 1024
querybuf:       resb 1024
bodybuf:        resb 65536
outbuf:         resb 131072
docroot:        resb 1024
filepath:       resb 4096
numtmp:         resb 32
status_tmp:     resd 1
ct_ptr_tmp:     resq 1

SECTION .text

; --- helpers ---

; write_str(fd=rdi, z=rsi)  [FIXED: compute length on rsi, keep fd intact]
write_str:
        push    rbx
        mov     rbx, rdi        ; save fd
        mov     rdi, rsi        ; strlen(z)
        call    strlen
        mov     rdx, rax        ; len
        mov     rdi, rbx        ; fd
        call    write
        pop     rbx
        ret

; write_raw(fd=rdi, buf=rsi, len=rdx)
write_raw:
        call    write
        ret

; itoa: rdi=value, rsi=buf -> rax=len
itoa_dec:
        push    rbx
        mov     rbx, 10
        xor     rcx, rcx
        cmp     rdi, 0
        jne     .nz
        mov     byte [rsi], '0'
        mov     rax, 1
        pop     rbx
        ret
.nz:    sub     rsp, 64
        mov     r8, rsp
        xor     rcx, rcx
.idiv:  xor     rdx, rdx
        mov     rax, rdi
        div     rbx
        add     dl, '0'
        mov     [r8+rcx], dl
        inc     rcx
        mov     rdi, rax
        test    rax, rax
        jnz     .idiv
        mov     rdx, rcx
        lea     r10, [r8+rcx-1]
        mov     r11, rsi
.rev:   cmp     rdx, 0
        je      .done
        mov     al, [r10]
        mov     [r11], al
        dec     r10
        inc     r11
        dec     rdx
        jmp     .rev
.done:  add     rsp, 64
        mov     rax, rcx
        pop     rbx
        ret

; logger to stderr: [METHOD PATH] STATUS BYTES\n
; rdi=method, rsi=path, rdx=status, rcx=len
log_line:
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12, rdi        ; method
        mov     r13, rsi        ; path
        mov     r14, rdx        ; status
        mov     r15, rcx        ; bytes

        ; "["
        mov     rdi, 2
        mov     byte [numtmp], '['
        mov     rsi, numtmp
        mov     rdx, 1
        call    write

        ; METHOD
        mov     rdi, 2
        mov     rsi, r12
        call    write_str

        ; " "
        mov     rdi, 2
        mov     byte [numtmp], ' '
        mov     rsi, numtmp
        mov     rdx, 1
        call    write

        ; PATH
        mov     rdi, 2
        mov     rsi, r13
        call    write_str

        ; "] "
        mov     rdi, 2
        mov     word [numtmp], 0x205D
        mov     rsi, numtmp
        mov     rdx, 2
        call    write

        ; STATUS
        mov     rdi, r14
        mov     rsi, numtmp
        call    itoa_dec
        mov     rdx, rax
        mov     rdi, 2
        mov     rsi, numtmp
        call    write

        ; " "
        mov     rdi, 2
        mov     byte [numtmp], ' '
        mov     rsi, numtmp
        mov     rdx, 1
        call    write

        ; BYTES
        mov     rdi, r15
        mov     rsi, numtmp
        call    itoa_dec
        mov     rdx, rax
        mov     rdi, 2
        mov     rsi, numtmp
        call    write

        ; "\n"
        mov     rdi, 2
        mov     byte [numtmp], 10
        mov     rsi, numtmp
        mov     rdx, 1
        call    write

        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret

; parse request line into methodbuf, pathbuf, querybuf
parse_request:
        mov     rsi, reqbuf
        mov     rdi, methodbuf
        xor     rcx, rcx
.m:     mov     al, [rsi]
        cmp     al, ' '
        je      .m_done
        mov     [rdi], al
        inc     rdi
        inc     rsi
        inc     rcx
        cmp     rcx, 15
        jb      .m
.m_done:mov     byte [rdi], 0
        inc     rsi ; skip space
        mov     rdi, pathbuf
        xor     rcx, rcx
.p:     mov     al, [rsi]
        cmp     al, ' '
        je      .p_done
        cmp     al, '?'
        je      .q_start
        mov     [rdi], al
        inc     rdi
        inc     rsi
        inc     rcx
        cmp     rcx, 1023
        jb      .p
.p_done:mov     byte [rdi], 0
        ret
.q_start:
        mov     byte [rdi], 0
        inc     rsi
        mov     rdi, querybuf
        xor     rcx, rcx
.q:     mov     al, [rsi]
        cmp     al, ' '
        je      .q_done
        mov     [rdi], al
        inc     rdi
        inc     rsi
        inc     rcx
        cmp     rcx, 1023
        jb      .q
.q_done:mov     byte [rdi], 0
        ret

; basic auth
check_basic:
        mov     rdi, hdrbuf
        mov     rsi, basic_prefix
        call    strstr
        test    rax, rax
        jz      .no
        mov     rdi, rax
        call    strlen
        add     rdi, rax             ; rdi -> base64 start
        mov     rsi, basic_good
        mov     rcx, 24
.cmp:   cmp     rcx, 0
        je      .yes
        mov     al, [rdi]
        mov     bl, [rsi]
        cmp     al, bl
        jne     .no
        inc     rdi
        inc     rsi
        dec     rcx
        jmp     .cmp
.yes:   mov     rax, 1
        ret
.no:    xor     rax, rax
        ret

; rdi=fd, rsi=hdrline, rdx=ctline, rcx=body_ptr, r8=body_len
send_with_hdr:
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12, rdi
        mov     r13, rsi
        mov     r14, rdx
        mov     r15, rcx
        mov     r9,  r8
        ; lines
        mov     rdi, r12
        mov     rsi, r13
        call    write_str
        mov     rdi, r12
        mov     rsi, server_hdr
        call    write_str
        mov     rdi, r12
        mov     rsi, r14
        call    write_str
        mov     rdi, r12
        mov     rsi, conn_close
        call    write_str
        mov     rdi, r12
        mov     rsi, cl_hdr
        call    write_str
        mov     rdi, r9
        mov     rsi, numtmp
        call    itoa_dec
        mov     rdx, rax
        mov     rdi, r12
        mov     rsi, numtmp
        call    write_raw
        mov     rdi, r12
        mov     rsi, crlf
        call    write_str
        mov     rdi, r12
        mov     rsi, crlf
        call    write_str
        ; body
        mov     rdi, r12
        mov     rsi, r15
        mov     rdx, r9
        call    write_raw
        ; log
        mov     rdi, methodbuf
        mov     rsi, pathbuf
        mov     rdx, 200
        cmp     r13, hdr_404
        jne     .check500
        mov     rdx, 404
        jmp     .log
.check500:
        cmp     r13, hdr_500
        jne     .log
        mov     rdx, 500
.log:
        mov     rcx, r9
        call    log_line
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret

; rdi=fd, rsi=filepath
serve_file:
        push    r12
        push    r13
        mov     r12, rdi
        mov     r13, rsi
        mov     rdi, r13
        mov     rsi, O_RDONLY
        call    open
        test    rax, rax
        js      .nf
        mov     r8, rax
        mov     rdi, r8
        xor     rsi, rsi
        mov     rdx, SEEK_END
        call    lseek
        test    rax, rax
        js      .nf_close
        mov     r9, rax
        cmp     r9, 65536
        ja      .nf_close
        mov     rdi, r8
        xor     rsi, rsi
        mov     rdx, SEEK_SET
        call    lseek
        mov     rdi, r8
        mov     rsi, bodybuf
        mov     rdx, r9
        call    read
        mov     rdi, r8
        call    close
        ; content-type heuristic
        mov     rdi, r13
        mov     rsi, ext_html
        call    strstr
        test    rax, rax
        jz      .as_text
        mov     rdx, ct_html
        jmp     .send
.as_text:
        mov     rdx, ct_text
.send:  mov     rdi, r12
        mov     rsi, hdr_200
        mov     rcx, bodybuf
        mov     r8,  r9
        call    send_with_hdr
        jmp     .done
.nf_close:
        mov     rdi, r8
        call    close
.nf:
        mov     rdi, r12
        mov     rsi, hdr_404
        mov     rdx, ct_text
        mov     rcx, nf_msg
        mov     r8,  nf_len
        call    send_with_hdr
.done:  pop     r13
        pop     r12
        ret

; rdi=client fd
handle_client:
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12, rdi
        xor     rbx, rbx
.read:
        mov     rdi, r12
        mov     rsi, reqbuf
        add     rsi, rbx
        mov     rdx, 4096
        call    read
        test    rax, rax
        jle     .err
        add     rbx, rax
        mov     byte [reqbuf+rbx], 0
        mov     rdi, reqbuf
        mov     rsi, crlfcrlf
        call    strstr
        test    rax, rax
        jz      .read
        ; copy headers into hdrbuf
        mov     r13, rax
        mov     rax, r13
        sub     rax, reqbuf
        cmp     rax, 8190
        jbe     .hl_ok
        mov     rax, 8190
.hl_ok: mov     rdi, hdrbuf
        mov     rsi, reqbuf
        mov     rdx, rax
        call    memcpy
        mov     byte [hdrbuf+rdx], 0
        ; parse request line
        call    parse_request
        ; method id (optional)
        xor     r15, r15
        mov     rdi, methodbuf
        mov     rsi, get_s
        call    strcmp
        test    rax, rax
        je      .meth_ok
        mov     rdi, methodbuf
        mov     rsi, post_s
        call    strcmp
        jne     .check_put
        mov     r15, 1
        jmp     .meth_ok
.check_put:
        mov     rdi, methodbuf
        mov     rsi, put_s
        call    strcmp
        jne     .check_del
        mov     r15, 2
        jmp     .meth_ok
.check_del:
        mov     rdi, methodbuf
        mov     rsi, delete_s
        call    strcmp
        jne     .meth_ok
        mov     r15, 3
.meth_ok:
        ; /hello
        mov     rdi, pathbuf
        mov     rsi, p_hello
        call    strcmp
        jne     .check_auth
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_text
        mov     rcx, hello_msg
        mov     r8,  hello_len
        call    send_with_hdr
        jmp     .done
.check_auth:
        mov     rdi, pathbuf
        mov     rsi, p_auth
        call    strcmp
        jne     .check_dyn
        call    check_basic
        test    rax, rax
        jz      .need_auth
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_html
        mov     rcx, ok_msg
        mov     r8,  ok_len
        call    send_with_hdr
        jmp     .done
.need_auth:
        mov     rdi, r12
        mov     rsi, hdr_401
        mov     rdx, ct_text
        mov     rcx, auth_msg
        mov     r8,  auth_len
        call    send_with_hdr
        jmp     .done
.check_dyn:
        ; startswith /dyn ?
        mov     rdi, pathbuf
        mov     rsi, p_dyn
        mov     rdx, 4
        call    strncmp
        test    rax, rax
        jne     .static
        ; Content-Length (optional)
        xor     r14, r14
        mov     rdi, hdrbuf
        mov     rsi, cl_key
        call    strstr
        test    rax, rax
        jz      .got_len
        add     rax, 15
.clsp:  mov     bl, [rax]
        cmp     bl, ' '
        jne     .clnum
        inc     rax
        jmp     .clsp
.clnum: xor     r14, r14
.cllp:  mov     bl, [rax]
        cmp     bl, '0'
        jb      .got_len
        cmp     bl, '9'
        ja      .got_len
        imul    r14, r14, 10
        sub     bl, '0'
        movzx   rdx, bl
        add     r14, rdx
        inc     rax
        jmp     .cllp
.got_len:
        ; body start
        mov     rdi, reqbuf
        mov     rsi, crlfcrlf
        call    strstr
        add     rax, 4
        mov     r10, rax
        ; copy body (bounded)
        mov     rax, reqbuf
        mov     r11, r10
        sub     r11, rax
        mov     rax, rbx
        sub     rax, r11
        mov     rdx, rax
        cmp     r14, 0
        je      .skipcpy
        cmp     rdx, r14
        jbe     .cpok
        mov     rdx, r14
.cpok:  mov     rdi, bodybuf
        mov     rsi, r10
        call    memcpy
.skipcpy:
        ; plugin_dispatch(method,path,query,body,len,out,cap,&status,&ct)
        mov     rdi, methodbuf
        mov     rsi, pathbuf
        mov     rdx, querybuf
        mov     rcx, bodybuf
        mov     r8,  r14
        mov     r9,  outbuf
        sub     rsp, 32                 ; keep 16B alignment
        mov     qword [ct_ptr_tmp], 0
        mov     dword [status_tmp], 200
        mov     qword [rsp], 65536      ; out_cap
        lea     rax, [rel status_tmp]
        mov     [rsp+8], rax            ; &status
        lea     rax, [rel ct_ptr_tmp]
        mov     [rsp+16], rax           ; &ct
        call    plugin_dispatch
        add     rsp, 32
        cmp     rax, 0
        jl      .err
        mov     r8,  rax
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_text
        mov     rcx, outbuf
        mov     rax, [ct_ptr_tmp]
        test    rax, rax
        jz      .sendplug
        mov     rdx, rax
.sendplug:
        call    send_with_hdr
        jmp     .done

.static:
        ; guard traversal
        mov     rdi, pathbuf
        mov     rsi, p_dotdot
        call    strstr
        test    rax, rax
        jnz     .err

        ; filepath = docroot + path (+ index.html if path ends with '/')
        ; len_docroot
        mov     rdi, docroot
        call    strlen
        mov     rcx, rax              ; rcx = pos in filepath
        ; copy docroot (without NUL)
        mov     rdi, filepath
        mov     rsi, docroot
        mov     rdx, rcx
        call    memcpy
        ; len_path
        mov     rdi, pathbuf
        call    strlen
        mov     rdx, rax
        ; append path (without NUL)
        mov     rdi, filepath
        add     rdi, rcx
        mov     rsi, pathbuf
        call    memcpy
        add     rcx, rdx
        ; NUL terminate for safety
        mov     byte [filepath+rcx], 0

        ; if path ends with '/', append index.html
        mov     rdi, pathbuf
        call    strlen
        cmp     byte [pathbuf+rax-1], '/'
        jne     .serve
        mov     rdi, idx_def
        call    strlen
        mov     rdx, rax
        mov     rdi, filepath
        add     rdi, rcx
        mov     rsi, idx_def
        call    memcpy
        add     rcx, rdx
        mov     byte [filepath+rcx], 0

.serve:
        mov     rdi, r12
        mov     rsi, filepath
        call    serve_file
        jmp     .done

.err:
        mov     rdi, r12
        mov     rsi, hdr_500
        mov     rdx, ct_text
        mov     rcx, sev_msg
        mov     r8,  sev_len
        call    send_with_hdr
.done:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        ret

; parse decimal string to u16: rdi=char* -> rax=value
ascii_to_u16:
        xor     rax, rax
        xor     rcx, rcx
.next:  mov     dl, [rdi+rcx]
        cmp     dl, 0
        je      .done
        cmp     dl, '0'
        jb      .done
        cmp     dl, '9'
        ja      .done
        imul    rax, rax, 10
        sub     dl, '0'
        movzx   rdx, dl
        add     rax, rdx
        inc     rcx
        jmp     .next
.done:  ret

; --- main(argc, argv) ---
main:
        ; Preserve argc/argv immediately
        mov     r12, rdi    ; argc
        mov     r13, rsi    ; argv

        ; defaults: docroot="./www"
        mov     rdi, defroot
        call    strlen
        mov     rdx, rax
        inc     rdx
        mov     rdi, docroot
        mov     rsi, defroot
        call    memcpy

        ; default port 8080
        mov     edi, 8080
        call    htons
        mov     [sin_port], ax

        ; parse args: -p <port> -d <docroot>
        cmp     r12, 1
        jle     .args_done
        mov     rcx, 1
.arg_loop:
        cmp     rcx, r12
        jge     .args_done
        mov     rbx, [r13 + rcx*8]
        mov     rdi, rbx
        lea     rsi, [rel arg_p]
        call    strcmp
        test    rax, rax
        jne     .check_d
        inc     rcx
        cmp     rcx, r12
        jge     .args_done
        mov     rdi, [r13 + rcx*8]
        call    ascii_to_u16
        mov     edi, eax
        call    htons
        mov     [sin_port], ax
        inc     rcx
        jmp     .arg_loop
.check_d:
        mov     rdi, rbx
        lea     rsi, [rel arg_d]
        call    strcmp
        test    rax, rax
        jne     .next
        inc     rcx
        cmp     rcx, r12
        jge     .args_done
        mov     rdi, [r13 + rcx*8]
        call    strlen
        mov     rdx, rax
        inc     rdx
        mov     rdi, docroot
        mov     rsi, [r13 + rcx*8]
        call    memcpy
        inc     rcx
        jmp     .arg_loop
.next:
        inc     rcx
        jmp     .arg_loop
.args_done:

        ; socket/bind/listen
        mov     edi, AF_INET
        mov     esi, SOCK_STREAM
        xor     edx, edx
        call    socket
        test    rax, rax
        js      .exit1
        mov     r12, rax
        mov     rdi, r12
        lea     rsi, [rel sin]
        mov     edx, 16
        call    bind
        test    rax, rax
        js      .exit1
        mov     rdi, r12
        mov     esi, 64
        call    listen
        test    rax, rax
        js      .exit1

.accept_loop:
        mov     rdi, r12
        xor     esi, esi
        xor     edx, edx
        call    accept
        test    rax, rax
        js      .accept_loop
        mov     r13, rax
        call    fork
        test    rax, rax
        jz      .child
        mov     rdi, r13
        call    close
        jmp     .accept_loop

.child:
        mov     rdi, r13
        call    handle_client
        mov     rdi, r13
        call    close
        xor     edi, edi
        call    exit

.exit1:
        mov     edi, 1
        call    exit
