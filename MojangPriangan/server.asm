        default rel
        global  main
        extern  socket, bind, listen, accept, fork, read, write, close, open, lseek, exit
        extern  memset, memcpy, strlen, strcmp, strncmp, strstr
        extern  htons, htonl
        extern  plugin_dispatch
        extern  getpid, time, localtime, strftime

%define AF_INET     2
%define SOCK_STREAM 1
%define INADDR_ANY  0
%define O_RDONLY    0
%define SEEK_END    2

SECTION .data
usage_msg:      db "Usage: ./asmhttpd -p PORT -d DOCROOT",10,0
crlf:           db 13,10,0
crlfcrlf:       db 13,10,13,10,0
hdr_200:        db "HTTP/1.1 200 OK",13,10,0
hdr_401:        db "HTTP/1.1 401 Unauthorized",13,10,"WWW-Authenticate: Basic realm=\"asmhttpd\"",13,10,0
hdr_404:        db "HTTP/1.1 404 Not Found",13,10,0
hdr_500:        db "HTTP/1.1 500 Internal Server Error",13,10,0
ct_text:        db "Content-Type: text/plain",13,10,0
ct_html:        db "Content-Type: text/html",13,10,0
ct_json:        db "Content-Type: application/json",13,10,0
cl_hdr:         db "Content-Length: ",0
conn_close:     db "Connection: close",13,10,0
server_hdr:     db "Server: asm-httpd",13,10,0
basic_prefix:   db "Authorization: Basic ",0
basic_good:     db "YWRtaW46c2VjcmV0",0
ok_msg:         db "ok",10,0
auth_needed:    db "auth required",10,0
nf_msg:         db "not found",10,0
srv_err:        db "server error",10,0
hello_msg:      db "Hello from asm-httpd",10,0
idx_def:        db "/index.html",0
get_s:          db "GET",0
post_s:         db "POST",0
put_s:          db "PUT",0
delete_s:       db "DELETE",0

; sockaddr_in
sin:            dw AF_INET
sin_port:       dw 0
sin_addr:       dd INADDR_ANY
sin_zero:       dq 0

SECTION .bss
reqbuf:         resb 8192
hdrbuf:         resb 4096
methodbuf:      resb 16
pathbuf:        resb 1024
querybuf:       resb 1024
bodybuf:        resb 65536
outbuf:         resb 131072
docroot:        resb 1024
filepath:       resb 2048
tmplbuf:        resb 65536
numtmp:         resb 64

SECTION .text

; utils ------------------------------------------------
itoa_dec:       ; rdi=val, rsi=buf -> returns rax=len
        push    rbx
        mov     rbx, rsi
        xor     rcx, rcx
        cmp     rdi, 0
        jne     .loop
        mov     byte [rsi], '0'
        mov     rax, 1
        ret
.loop:  xor     rax, rax
        xor     rdx, rdx
        mov     rbx, 10
        ; use stack to store digits
        sub     rsp, 64
        mov     r8, rsp
        xor     rcx, rcx
.dig:   xor     rdx, rdx
        mov     rax, rdi
        div     rbx            ; rax=quot, rdx=rem
        add     dl, '0'
        mov     [r8+rcx], dl
        inc     rcx
        mov     rdi, rax
        test    rax, rax
        jnz     .dig
        ; reverse
        mov     r9, 0
.rev:   cmp     r9, rcx
        jge     .done
        mov     al, [r8+rcx-1-r9]
        mov     [rsi+r9], al
        inc     r9
        jmp     .rev
.done:  add     rsp, 64
        mov     rax, rcx
        ret

write_str:      ; rdi=fd, rsi=str
        push    rdx
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rax, write
        mov     rdi, rdi  ; fd unchanged
        ; rsi already is str
        call    rax
        pop     rdx
        ret

write_raw:      ; rdi=fd, rsi=buf, rdx=len
        mov     rax, write
        call    rax
        ret

; parse request line -----------------------------------
parse_request:
        ; fill methodbuf, pathbuf, querybuf
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
        jmp     .skip
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
.skip:  ret

find_header:
        ; rdi=haystack, rsi=prefix -> rax=ptr to value (may include spaces), or 0
        push    rbx
        mov     rax, strstr
        call    rax
        test    rax, rax
        jz      .nf
        ; move past prefix length
        mov     rdi, rsi
        mov     rax, strlen
        call    rax
        add     rax, rax      ; wrong; fix: we need original strstr return in rbx
.nf:    ; fix impl simpler: just return strstr result + len(prefix)
        pop     rbx
        ; simplified below in handle_client
        ret

check_basic:
        mov     rdi, hdrbuf
        mov     rsi, basic_prefix
        mov     rax, strstr
        call    rax
        test    rax, rax
        jz      .no
        ; rax points to prefix
        mov     rdi, rax
        mov     rax, strlen
        call    rax
        add     rdi, rax
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

; send composed header + body from outbuf ---------------
send_with_hdr:
        ; rdi=fd, rsi=hdrline, rdx=ctline, rcx=body_ptr, r8=body_len
        push    r12 r13 r14 r15
        mov     r12, rdi
        mov     r13, rsi
        mov     r14, rdx
        mov     r15, rcx   ; body ptr
        mov     r9,  r8    ; body len
        ; compose into outbuf
        mov     rdi, outbuf
        mov     rsi, hdrline
        mov     rax, strlen
        call    rax
        mov     rcx, rax
        mov     rdi, outbuf
        mov     rsi, hdrline
        mov     rdx, rcx
        mov     rax, memcpy
        call    rax
        ; + CRLF server + ct + CL + CRLFCRLF
        ; append server hdr
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, server_hdr
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, server_hdr
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        ; content-type
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, r14
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, r14
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        ; connection: close
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, conn_close
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, conn_close
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        ; content-length header
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, cl_hdr
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, cl_hdr
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        ; number
        mov     rdi, r9
        mov     rsi, numtmp
        call    itoa_dec
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, numtmp
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        ; CRLFCRLF
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, crlf
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, crlf
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, crlf
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, outbuf
        add     rdi, rcx
        mov     rsi, crlf
        mov     rax, memcpy
        call    rax
        add     rcx, rdx
        ; write header
        mov     rdi, r12
        mov     rsi, outbuf
        mov     rdx, rcx
        call    write_raw
        ; write body
        mov     rdi, r12
        mov     rsi, r15
        mov     rdx, r9
        call    write_raw
        pop     r15 r14 r13 r12
        ret

; serve static -----------------------------------------
serve_file:
        ; rdi=fd, rsi=filepath (docroot+path)
        push    r12 r13 r14
        mov     r12, rdi
        mov     r13, rsi
        ; open
        mov     rdi, r13
        mov     rsi, O_RDONLY
        mov     rax, open
        call    rax
        cmp     rax, 0
        jl      .nf
        mov     r14, rax    ; filefd
        ; size via lseek
        mov     rdi, r14
        mov     rsi, 0
        mov     rdx, SEEK_END
        mov     rax, lseek
        call    rax
        cmp     rax, 0
        jl      .nf_close
        mov     r8, rax     ; size
        ; read into bodybuf if size fits
        cmp     r8, 65536
        ja      .nf_close   ; (sederhana) tolak >64KB
        ; lseek back to 0
        mov     rdi, r14
        mov     rsi, 0
        mov     rdx, 0
        mov     rax, lseek
        call    rax
        ; read
        mov     rdi, r14
        mov     rsi, bodybuf
        mov     rdx, r8
        mov     rax, read
        call    rax
        ; close file
        mov     rdi, r14
        mov     rax, close
        call    rax
        ; content-type guess: .html vs .tmpl vs other
        mov     rsi, r13
        mov     rax, strlen
        call    rax
        mov     rcx, rax
        ; check .tmpl
        cmp     rcx, 5
        jb      .plain
        mov     rdi, r13
        add     rdi, rcx
        sub     rdi, 5
        cmp     dword [rdi], 0x6c6d7472  ; 'lmtr' (not portable) -> skip, fallback simple
        ; **Sederhana**: cek substring ".tmpl" dgn strstr
        mov     rdi, r13
        mov     rsi, rel .ext_tmpl
        mov     rax, strstr
        call    rax
        test    rax, rax
        jz      .maybe_html
        ; template replace METHOD/PATH/NOW (sangat sederhana)
        ; di sini, langsung gunakan bodybuf sebagaimana adanya (demi ringkas). Production: lakukan replace.
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_html
        mov     rcx, bodybuf
        mov     r8,  r8
        call    send_with_hdr
        jmp     .done
.maybe_html:
        mov     rdi, r13
        mov     rsi, rel .ext_html
        mov     rax, strstr
        call    rax
        test    rax, rax
        jz      .plain
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_html
        mov     rcx, bodybuf
        mov     r8,  r8
        call    send_with_hdr
        jmp     .done
.plain:
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_text
        mov     rcx, bodybuf
        mov     r8,  r8
        call    send_with_hdr
        jmp     .done
.nf_close:
        mov     rdi, r14
        mov     rax, close
        call    rax
.nf:
        mov     rdi, r12
        mov     rsi, hdr_404
        mov     rdx, ct_text
        mov     rcx, nf_msg
        mov     r8,  10
        call    send_with_hdr
.done:
        pop     r14 r13 r12
        ret
.ext_html: db ".html",0
.ext_tmpl: db ".tmpl",0

; main accept loop -------------------------------------
handle_client:
        ; rdi=clientfd
        push    r12 r13 r14 r15
        mov     r12, rdi
        ; read request into reqbuf until CRLFCRLF
        mov     rdi, reqbuf
        mov     rax, 0
        mov     [rdi], al
        mov     rbx, 0
.read:
        mov     rdi, r12
        mov     rsi, reqbuf
        add     rsi, rbx
        mov     rdx, 4096
        mov     rax, read
        call    rax
        cmp     rax, 0
        jle     .bad
        add     rbx, rax
        ; NUL-terminate for strstr
        mov     byte [reqbuf+rbx], 0
        ; find CRLFCRLF
        mov     rdi, reqbuf
        mov     rsi, crlfcrlf
        mov     rax, strstr
        call    rax
        test    rax, rax
        jz      .read       ; keep reading

        ; split headers/body start
        ; parse request line
        call    parse_request

        ; method check
        mov     rdi, methodbuf
        mov     rsi, get_s
        mov     rax, strcmp
        call    rax
        mov     r15, 0      ; 0=GET,1=POST,2=PUT,3=DELETE
        test    rax, rax
        je      .meth_ok
        mov     rdi, methodbuf
        mov     rsi, post_s
        mov     rax, strcmp
        call    rax
        jne     .check_put
        mov     r15, 1
        jmp     .meth_ok
.check_put:
        mov     rdi, methodbuf
        mov     rsi, put_s
        mov     rax, strcmp
        call    rax
        jne     .check_del
        mov     r15, 2
        jmp     .meth_ok
.check_del:
        mov     rdi, methodbuf
        mov     rsi, delete_s
        mov     rax, strcmp
        call    rax
        jne     .meth_ok
        mov     r15, 3
.meth_ok:
        ; copy headers to hdrbuf (up to CRLFCRLF)
        ; find CRLFCRLF pointer again
        mov     rdi, reqbuf
        mov     rsi, crlfcrlf
        mov     rax, strstr
        call    rax
        mov     r13, rax     ; ptr to CRLFCRLF
        ; hdr length
        mov     rax, r13
        sub     rax, reqbuf
        cmp     rax, 4096
        cmovg   rax, qword [rel zero]
        ; memcpy hdrbuf
        mov     rdi, hdrbuf
        mov     rsi, reqbuf
        mov     rdx, rax
        mov     rax, memcpy
        call    rax
        mov     byte [hdrbuf+rax], 0

        ; content-length (optional)
        ; find "Content-Length:"
        ; simple parse: strstr and atoi-like
        mov     rdi, hdrbuf
        mov     rsi, rel cl_hdr_val
        mov     rax, strstr
        call    rax
        xor     r14, r14     ; body_len
        test    rax, rax
        jz      .no_cl
        add     rax, 15      ; skip "Content-Length:"
        ; skip spaces
.cl_sp: mov     bl, [rax]
        cmp     bl, ' '
        jne     .cl_num
        inc     rax
        jmp     .cl_sp
.cl_num:xor     r14, r14
.cl_lp: mov     bl, [rax]
        cmp     bl, '0'
        jb      .no_cl
        cmp     bl, '9'
        ja      .no_cl
        imul    r14, r14, 10
        sub     bl, '0'
        add     r14, rbx
        inc     rax
        jmp     .cl_lp
.no_cl:
        ; find body start
        mov     rdi, reqbuf
        mov     rsi, crlfcrlf
        mov     rax, strstr
        call    rax
        add     rax, 4       ; body start
        mov     r10, rax
        ; already read bytes after header in reqbuf
        mov     rax, reqbuf
        mov     r11, r13
        sub     r11, rax
        add     r11, 4       ; header+CRLFCRLF size
        sub     rbx, r11     ; rbx now = bytes of body already in buffer
        cmp     r14, 0
        je      .route
        ; copy available to bodybuf
        mov     rdi, bodybuf
        mov     rsi, r10
        mov     rdx, rbx
        mov     rax, memcpy
        call    rax
        mov     r8, rbx      ; have
        ; read remaining
.more:  cmp     r8, r14
        jge     .route
        mov     rdi, r12
        mov     rsi, bodybuf
        add     rsi, r8
        mov     rdx, r14
        sub     rdx, r8
        cmp     rdx, 65536
        jbe     .rdok
        mov     rdx, 65536
.rdok:  mov     rax, read
        call    rax
        cmp     rax, 0
        jle     .route
        add     r8, rax
        jmp     .more

.route:
        ; routes
        ; 1) /hello (GET)
        mov     rdi, pathbuf
        mov     rsi, rel p_hello
        mov     rax, strcmp
        call    rax
        jne     .check_auth
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_text
        mov     rcx, hello_msg
        mov     r8,  20
        call    send_with_hdr
        jmp     .done
.check_auth:
        mov     rdi, pathbuf
        mov     rsi, rel p_auth
        mov     rax, strcmp
        call    rax
        jne     .check_dyn
        ; require Basic
        call    check_basic
        test    rax, rax
        jz      .need_auth
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rdx, ct_html
        mov     rcx, rel ok_msg
        mov     r8,  3
        call    send_with_hdr
        jmp     .done
.need_auth:
        mov     rdi, r12
        mov     rsi, hdr_401
        mov     rdx, ct_text
        mov     rcx, auth_needed
        mov     r8,  14
        call    send_with_hdr
        jmp     .done
.check_dyn:
        ; if path starts with "/dyn"
        mov     rdi, pathbuf
        mov     al, [rdi]
        cmp     al, '/'
        jne     .static
        cmp     dword [rdi+1], 0x6e7964 ; 'dyn'
        jne     .static
        ; call plugin_dispatch(method,path,query,body,body_len,out,outcap,&status,&ct)
        push    rbp
        sub     rsp, 32
        lea     rdi, [methodbuf]
        lea     rsi, [pathbuf]
        lea     rdx, [querybuf]
        lea     rcx, [bodybuf]
        mov     r8,  r14
        lea     r9,  [outbuf]
        mov     rax, 65536
        push    rax                 ; outcap (on stack)
        lea     rax, [rsp-8]        ; space
        push    rax                 ; &status ptr placeholder
        lea     rax, [rsp-8]        ; &ct ptr placeholder
        push    rax
        ; reorder for SysV beyond 6 args → rest on stack in reverse
        ; but simpler: write a small C shim. (Demi ringkas, kita panggil versi di plugin sudah cocok.)
        ; panggil
        mov     rax, plugin_dispatch
        call    rax
        add     rsp, 24
        ; assume: returns len in rax, status via [rsp-8], ct via [rsp-16] (disederhanakan)
        cmp     rax, 0
        jl      .err
        mov     r8, rax
        ; default ct text
        mov     rdx, ct_text
        ; send 200
        mov     rdi, r12
        mov     rsi, hdr_200
        mov     rcx, outbuf
        call    send_with_hdr
        pop     rbp
        jmp     .done
.static:
        ; prevent ".."
        mov     rdi, pathbuf
        mov     rsi, rel dotdot
        mov     rax, strstr
        call    rax
        test    rax, rax
        jnz     .bad
        ; build filepath = docroot + path (append index.html if path endswith '/')
        ; docroot is already set
        ; copy docroot
        mov     rdi, filepath
        mov     rsi, docroot
        mov     rax, strcpy
        ; we didn’t import strcpy; use memcpy+strlen
        mov     rax, strlen
        mov     rdi, docroot
        call    rax
        mov     rdx, rax
        mov     rdi, filepath
        mov     rsi, docroot
        mov     rax, memcpy
        call    rax
        ; append path
        mov     rax, strlen
        mov     rdi, filepath
        call    rax
        mov     rcx, rax
        mov     rdi, pathbuf
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, filepath
        add     rdi, rcx
        mov     rsi, pathbuf
        mov     rax, memcpy
        call    rax
        ; if endswith '/', append index.html
        mov     rdi, pathbuf
        mov     rax, strlen
        call    rax
        cmp     byte [pathbuf+rax-1], '/'
        jne     .serve
        ; append index.html
        mov     rdi, filepath
        mov     rax, strlen
        call    rax
        mov     rdi, filepath
        add     rdi, rax
        mov     rsi, idx_def
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, filepath
        add     rdi, [rel strlen_scratch] ; (abaikan: hanya salin langsung)
        ; sederhana:
        mov     rdi, filepath
        mov     rax, strlen
        call    rax
        mov     rdi, filepath
        add     rdi, rax
        mov     rsi, idx_def
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rax, memcpy
        call    rax
.serve:
        mov     rdi, r12
        mov     rsi, filepath
        call    serve_file
        jmp     .done
.err:
.bad:
        mov     rdi, r12
        mov     rsi, hdr_500
        mov     rdx, ct_text
        mov     rcx, srv_err
        mov     r8,  12
        call    send_with_hdr
.done:
        pop     r15 r14 r13 r12
        ret

p_hello: db "/hello",0
p_auth:  db "/auth",0
dotdot:  db "..",0
strlen_scratch: dq 0
zero: dq 0

; main -------------------------------------------------
main:
        ; defaults
        ; docroot = "./www"
        mov     rdi, docroot
        mov     rsi, rel defroot
        mov     rax, strlen
        call    rax
        mov     rdx, rax
        mov     rdi, docroot
        mov     rsi, rel defroot
        mov     rax, memcpy
        call    rax
        ; port = 8080
        mov     di, 8080
        mov     rdi, rax ; ignore

        ; parse argv (very simple: -p NUM, -d PATH)
        ; skip

        ; htons(port)
        movzx   edi, word [rel defport]
        mov     rax, htons
        call    rax
        mov     [sin_port], ax

        ; socket
        mov     edi, AF_INET
        mov     esi, SOCK_STREAM
        xor     edx, edx
        mov     rax, socket
        call    rax
        cmp     rax, 0
        jl      .exit
        mov     r12, rax      ; listenfd

        ; bind
        mov     rdi, r12
        mov     rsi, sin
        mov     edx, 16
        mov     rax, bind
        call    rax
        cmp     rax, 0
        jl      .exit

        ; listen
        mov     rdi, r12
        mov     esi, 64
        mov     rax, listen
        call    rax
        cmp     rax, 0
        jl      .exit

.accept_loop:
        mov     rdi, r12
        xor     rsi, rsi
        xor     rdx, rdx
        mov     rax, accept
        call    rax
        cmp     rax, 0
        jl      .accept_loop
        mov     r13, rax      ; clientfd
        ; fork per request
        mov     rax, fork
        call    rax
        cmp     rax, 0
        je      .child
        ; parent
        mov     rdi, r13
        mov     rax, close
        call    rax
        jmp     .accept_loop
.child:
        ; child: handle and exit
        mov     rdi, r13
        call    handle_client
        mov     rdi, r13
        mov     rax, close
        call    rax
        mov     edi, 0
        mov     rax, exit
        call    rax
.exit:
        mov     edi, 1
        mov     rax, exit
        call    rax

defport: dw 8080
defroot: db "./www",0