#include <string.h>

// Returns 1 if the path is safe, 0 otherwise.
int is_path_safe(const char* path) {
    if (strstr(path, "..")) {
        return 0; // Unsafe, contains ".."
    }
    return 1; // Safe
}