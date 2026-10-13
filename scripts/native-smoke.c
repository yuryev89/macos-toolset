#include "CSnapshot.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
static pid_t fixture = -1;
static volatile sig_atomic_t stopping = 0;
static void stop(int signal) { (void)signal; stopping = 1; }
static void cleanup(void) {
    if (fixture > 1) { kill(fixture, SIGTERM); while(waitpid(fixture, NULL, 0)<0 && errno==EINTR) {} fixture=-1; }
}
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); exit(1); } } while(0)
int main(void) {
    atexit(cleanup);
    TSProcess *rows = NULL; size_t count = 0;
    int inventory_error = ts_snapshot(&rows, &count);
    if (inventory_error) fprintf(stderr,"inventory errno: %d\n",inventory_error);
    CHECK(inventory_error==0);
    CHECK(count>0);
    ts_free_snapshot(rows);
    CHECK(ts_snapshot(NULL, &count)==EINVAL);
    CHECK(ts_signal_checked(0,0,0,0)==EPERM);
    CHECK(ts_signal_checked(1,0,0,1)==EPERM);
    CHECK(ts_signal_checked(getpid(),0,0,0)==EPERM);
    fixture=fork(); CHECK(fixture>=0);
    if(fixture==0) {
        signal(SIGTERM,stop);
        pid_t zombie=fork();
        if(zombie<0) _exit(2);
        if(zombie==0) _exit(0);
        while(!stopping) usleep(10000);
        while(waitpid(zombie,NULL,0)<0 && errno==EINTR) {}
        _exit(0);
    }
    TSProcess parent={0}; int found=0;
    for(int attempt=0;attempt<200 && !found;attempt++) {
        CHECK(ts_snapshot(&rows,&count)==0);
        int zombies=0;
        for(size_t i=0;i<count;i++) {
            if(rows[i].pid==fixture) parent=rows[i];
            if(rows[i].ppid==fixture && rows[i].zombie) zombies++;
        }
        found=parent.pid==fixture && zombies==1;
        ts_free_snapshot(rows); if(!found) usleep(10000);
    }
    CHECK(found);
    CHECK(ts_signal_checked(fixture,parent.start_seconds+1,parent.start_microseconds,0)==ESTALE);
    CHECK(ts_signal_checked(fixture,parent.start_seconds,parent.start_microseconds+1,1)==ESTALE);
    CHECK(kill(fixture,0)==0);
    CHECK(ts_signal_checked(fixture,parent.start_seconds,parent.start_microseconds,0)==0);
    int status=0; CHECK(waitpid(fixture,&status,0)==fixture); fixture=-1;
    CHECK(WIFEXITED(status) && WEXITSTATUS(status)==0);
    fixture=fork(); CHECK(fixture>=0);
    if(fixture==0) { while(1) pause(); }
    CHECK(ts_snapshot(&rows,&count)==0);
    parent=(TSProcess){0};
    for(size_t i=0;i<count;i++) if(rows[i].pid==fixture) parent=rows[i];
    ts_free_snapshot(rows);
    CHECK(parent.pid==fixture);
    CHECK(ts_signal_checked(fixture,parent.start_seconds,parent.start_microseconds,0)==EBUSY);
    CHECK(ts_signal_checked(fixture,parent.start_seconds,parent.start_microseconds,1)==EBUSY);
    CHECK(kill(fixture,0)==0);
    cleanup();
    puts("PASS inventory, owned zombie, stale identity, protected PID, checked TERM, no-zombie TERM/KILL rejection, fixtures reaped");
    return 0;
}
