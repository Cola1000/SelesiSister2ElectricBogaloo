#include "plugin_api.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
static const char* CT_JSON = "Content-Type: application/json\r\n";
static const char* CT_TEXT = "Content-Type: text/plain\r\n";
static int starts_with(const char* s, const char* p){ return strncmp(s,p,strlen(p))==0; }
static int url_param_int(const char* q, const char* key, int* out){
  if(!q||!key) return 0;
  size_t k = strlen(key);
  const char* p = q;
  while(p && *p){
    if(strncmp(p,key,k)==0 && p[k]=='='){ *out = atoi(p+k+1); return 1; }
    p = strchr(p,'&'); if(p) ++p;
  }
  return 0;
}
int plugin_dispatch(const char* method,
                    const char* path,
                    const char* query,
                    const char* body,
                    int   body_len,
                    char* out,
                    int   out_cap,
                    int*  out_status,
                    const char** out_ct){
  (void)method; (void)body; (void)body_len;
  if(!path||!out||out_cap<=0) return -1;
  if(starts_with(path, "/dyn/hello")){
    int n = snprintf(out, out_cap, "Hello from C plugin!\\n");
    if(out_ct) *out_ct = CT_TEXT;
    if(out_status) *out_status = 200;
    return n;
  }
  if(starts_with(path, "/dyn/add")){
    int a=0,b=0; url_param_int(query,"a",&a); url_param_int(query,"b",&b);
    int n = snprintf(out, out_cap, "{\"a\":%d,\"b\":%d,\"sum\":%d}\n", a,b,a+b);
    if(out_ct) *out_ct = CT_JSON;
    if(out_status) *out_status = 200;
    return n;
  }
  if(out_status) *out_status = 404;
  if(out_ct) *out_ct = CT_TEXT;
  return snprintf(out, out_cap, "dynamic route not found\\n");
}
