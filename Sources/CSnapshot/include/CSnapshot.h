#ifndef CSNAPSHOT_H
#define CSNAPSHOT_H
#include <stddef.h>
#include <stdint.h>
typedef struct {
    int32_t pid, ppid;
    uint64_t start_seconds, start_microseconds;
    int zombie;
    char name[256];
    char path[4096];
} TSProcess;
/* Returns zero on success or an errno value. Outputs are cleared on failure. */
int ts_snapshot(TSProcess **rows, size_t *count);
void ts_free_snapshot(TSProcess *rows);
/* Rejects protected targets, stale identities and parents without zombies.
   Validation and signaling are not atomic; no portable PID handle exists here. */
int ts_signal_checked(int32_t pid, uint64_t seconds, uint64_t microseconds, int force);
#endif
