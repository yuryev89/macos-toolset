#include "CSnapshot.h"
#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#include <unistd.h>

int ts_snapshot(TSProcess **rows, size_t *count) {
    if (rows) *rows = NULL;
    if (count) *count = 0;
    if (!rows || !count) return EINVAL;
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    struct kinfo_proc *inventory = NULL;
    size_t bytes = 0;
    int completed = 0;
    /* The process table can grow between sizing and reading. Never publish
       partial ENOMEM results; bounded retries prevent an unbounded stall. */
    for (int attempt = 0; attempt < 8; attempt++) {
        size_t needed = 0;
        if (sysctl(mib, 4, NULL, &needed, NULL, 0) < 0) return errno;
        if (!needed) return EIO;
        if (needed > SIZE_MAX - needed / 4 - 32 * sizeof(*inventory)) return EOVERFLOW;
        bytes = needed + needed / 4 + 32 * sizeof(*inventory);
        inventory = malloc(bytes);
        if (!inventory) return ENOMEM;
        if (sysctl(mib, 4, inventory, &bytes, NULL, 0) == 0) { completed = 1; break; }
        int error = errno;
        free(inventory); inventory = NULL;
        if (error != ENOMEM) return error;
    }
    if (!completed) return EAGAIN;
    if (!bytes || bytes % sizeof(*inventory)) { free(inventory); return EIO; }
    size_t length = bytes / sizeof(*inventory);
    TSProcess *result = calloc(length, sizeof(*result));
    if (!result) { free(inventory); return ENOMEM; }
    for (size_t i = 0; i < length; i++) {
        struct extern_proc *process = &inventory[i].kp_proc;
        TSProcess *row = &result[i];
        row->pid = process->p_pid;
        row->ppid = inventory[i].kp_eproc.e_ppid;
        row->start_seconds = (uint64_t)process->p_starttime.tv_sec;
        row->start_microseconds = (uint64_t)process->p_starttime.tv_usec;
        row->zombie = process->p_stat == SZOMB;
        strlcpy(row->name, process->p_comm, sizeof(row->name));
        /* Path is optional display metadata: zombies and protected processes
           often have no readable executable path. State comes from sysctl. */
        if (row->pid > 0 && !row->zombie && proc_pidpath(row->pid, row->path, sizeof(row->path)) <= 0)
            row->path[0] = '\0';
    }
    free(inventory);
    *rows = result; *count = length;
    return 0;
}

void ts_free_snapshot(TSProcess *rows) { free(rows); }

static int validate_identity(int32_t pid, uint64_t seconds, uint64_t microseconds) {
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    struct kinfo_proc process = {0};
    size_t bytes = sizeof(process);
    if (sysctl(mib, 4, &process, &bytes, NULL, 0) < 0) return errno;
    if (!bytes) return ESRCH;
    if (bytes != sizeof(process)) return EIO;
    if (process.kp_proc.p_pid != pid ||
        (uint64_t)process.kp_proc.p_starttime.tv_sec != seconds ||
        (uint64_t)process.kp_proc.p_starttime.tv_usec != microseconds) return ESTALE;
    if (process.kp_proc.p_stat == SZOMB) return ESRCH;
    return 0;
}

int ts_signal_checked(int32_t pid, uint64_t seconds, uint64_t microseconds, int force) {
    if (pid <= 1 || pid == getpid()) return EPERM;
    if (!seconds || microseconds >= 1000000 || (force != 0 && force != 1)) return EINVAL;
    int error = validate_identity(pid, seconds, microseconds);
    if (error) return error;
    TSProcess *rows = NULL;
    size_t count = 0;
    error = ts_snapshot(&rows, &count);
    if (error) return error;
    int same_parent = 0, has_zombies = 0;
    for (size_t i = 0; i < count; i++) {
        if (rows[i].pid == pid && rows[i].start_seconds == seconds &&
            rows[i].start_microseconds == microseconds && !rows[i].zombie) same_parent = 1;
        if (rows[i].ppid == pid && rows[i].zombie) has_zombies = 1;
    }
    ts_free_snapshot(rows);
    if (!same_parent) return ESTALE;
    if (!has_zombies) return EBUSY;
    /* Revalidate after potentially slow path lookups. Darwin kill remains a
       PID API, so a very small identity-check/signal race is unavoidable. */
    error = validate_identity(pid, seconds, microseconds);
    if (error) return error;
    if (kill(pid, force ? SIGKILL : SIGTERM) < 0) return errno;
    return 0;
}
