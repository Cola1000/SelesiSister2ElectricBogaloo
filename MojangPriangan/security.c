#include <stddef.h>
#include <stdint.h>

int is_path_safe(const char *p) {
    if (!p || !*p) return 0;

    // Must start with "www/"
    if (p[0] != 'w' || p[1] != 'w' || p[2] != 'w' || p[3] != '/') return 0;

    // walk after "www/"
    p += 4;
    if (!*p) return 0;

    int seen_dot = 0;
    for (; *p; ++p) {
        char c = *p;
        if (c == '.') seen_dot = 1;
        if (c == '.' && p[1] == '.') return 0;      // no ".."
        if (c == '/') return 0;                     // no subdirs
        if (!((c >= 'a' && c <= 'z') ||
              (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') ||
              c == '.' || c == '-' || c == '_'))    // allow underscore
            return 0;
    }
    // require an extension like ".txt", ".html" etc.
    return seen_dot ? 1 : 0;
}