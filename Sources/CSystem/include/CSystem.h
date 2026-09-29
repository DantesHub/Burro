// Read-only process inspection and system SQLite bindings.
#include <sqlite3.h>
#include <stdint.h>
#include <sys/types.h>

typedef struct {
    int pid;
    int ppid;
    unsigned int uid;
    uint64_t started;
    int cwd_readable;
    char executable[4096];
    char cwd[4096];
} BurroProcess;
int burro_list_pids(int *buffer, int capacity);
int burro_process_info(int pid, BurroProcess *result);
// 1 held by another process, 0 free, -1 unreadable. Never creates a lock.
int burro_lock_held(const char *path);

// 1 writable stdout/stderr vnode path, 0 closed/non-vnode/read-only, -1 inspection denied.
int burro_process_output_path(int pid, int fd, char *path, int capacity);
