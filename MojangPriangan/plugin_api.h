#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int plugin_dispatch(const char* method,
                    const char* path,
                    const char* query,
                    const char* body,
                    int   body_len,
                    char* out,
                    int   out_cap,
                    int*  out_status,
                    const char** out_ct);
#ifdef __cplusplus
}
#endif
