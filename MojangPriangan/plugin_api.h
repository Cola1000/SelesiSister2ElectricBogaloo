#ifndef PLUGIN_API_H
#define PLUGIN_API_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

// Dipanggil server.asm untuk route yang diawali "/dyn".
// Harus mengisi "out" dengan body (plain text/JSON/HTML), dan return length body.
// Return <0 untuk error -> server kirim 500.
int plugin_dispatch(const char* method,
                    const char* path,
                    const char* query,
                    const char* body,
                    int body_len,
                    char* out,
                    int out_cap,
                    int* out_status,   // status HTTP (mis. 200/400/404)
                    const char** out_ct // content-type (mis. "text/plain")
);

#ifdef __cplusplus
}
#endif
#endif