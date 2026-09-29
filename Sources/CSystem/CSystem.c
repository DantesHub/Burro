// Query the kernel instead of trusting stale PID or lock files.
#include "CSystem.h"
#include <libproc.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
int burro_list_pids(int *buffer, int capacity) {
    return proc_listallpids(buffer, capacity * (int)sizeof(int));
}
int burro_process_info(int pid, BurroProcess *result) {
    struct proc_bsdinfo bsd;
    memset(result, 0, sizeof(*result));
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sizeof(bsd)) != sizeof(bsd)) return 0;
    result->pid = pid; result->ppid = bsd.pbi_ppid;
    result->uid = bsd.pbi_uid; result->started = bsd.pbi_start_tvsec;
    proc_pidpath(pid, result->executable, sizeof(result->executable));
    struct proc_vnodepathinfo vnode;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, sizeof(vnode)) == sizeof(vnode)) {
        strncpy(result->cwd, vnode.pvi_cdir.vip_path, sizeof(result->cwd)-1);
        result->cwd_readable = 1;
    }
    return 1;
}
int burro_lock_held(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return errno == ENOENT ? 0 : -1;
    int result = flock(fd, LOCK_EX | LOCK_NB);
    int saved = errno;
    if (result == 0) flock(fd, LOCK_UN);
    close(fd);
    return result == 0 ? 0 : ((saved == EWOULDBLOCK || saved == EAGAIN) ? 1 : -1);
}

int burro_process_output_path(int pid, int fd, char *path, int capacity) {
    if ((fd != 1 && fd != 2) || capacity < 2) return -1;
    path[0] = 0;
    struct vnode_fdinfowithpath info;
    int size = proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, &info, sizeof(info));
    if (size != sizeof(info)) {
        // Pipes/sockets and a process that exited between snapshots have no task vnode.
        return (errno == EBADF || errno == ESRCH || errno == ENOENT ||
                errno == EINVAL || errno == ENOTSUP) ? 0 : -1;
    }
    if (!(info.pfi.fi_openflags & FWRITE)) return 0;
    strncpy(path, info.pvip.vip_path, capacity - 1);
    path[capacity - 1] = 0;
    return path[0] ? 1 : 0;
}
