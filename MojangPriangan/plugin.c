#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "plugin_api.h"

static int kv_get(const char* q, const char* key, int* out){
    if(!q) return 0;
    size_t klen = strlen(key);
    const char* p = q;
    while(p && *p){
        const char* amp = strchr(p, '&');
        size_t seglen = amp ? (size_t)(amp - p) : strlen(p);
        if(seglen > klen+1 && !strncmp(p, key, klen) && p[klen]=='='){
            *out = atoi(p + klen + 1);
            return 1;
        }
        p = amp ? amp+1 : NULL;
    }
    return 0;
}

int plugin_dispatch(const char* method,
                    const char* path,
                    const char* query,
                    const char* body,
                    int body_len,
                    char* out,
                    int out_cap,
                    int* out_status,
                    const char** out_ct){
    (void)body; (void)body_len;
    *out_status = 200; *out_ct = "text/plain";

    if(!strncmp(path, "/dyn/hello", 10)){
        const char* msg = "Ngalegaan kakawasan ti C plugin!";
        int n = (int)strlen(msg);
        if(n>out_cap) return -1;
        memcpy(out, msg, n);
        return n;
    }
    else if(!strncmp(path, "/dyn/add", 8)){
        int a=0,b=0;
        if(!kv_get(query, "a", &a) || !kv_get(query, "b", &b)){
            const char* msg = "missing a or b";
            *out_status = 400;
            int n=(int)strlen(msg); if(n>out_cap) return -1; memcpy(out,msg,n); return n;
        }
        int sum = a+b;
        int n = snprintf(out, out_cap, "{\"a\":%d,\"b\":%d,\"sum\":%d}", a,b,sum);
        *out_ct = "application/json";
        return (n<0||n>out_cap)?-1:n;
    }

    *out_status = 404;
    const char* msg = "not found";
    int n=(int)strlen(msg); if(n>out_cap) return -1; memcpy(out,msg,n); return n;
}