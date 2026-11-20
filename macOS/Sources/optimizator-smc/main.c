// optimizator-smc — маленький помічник з правами root (встановлюється один раз у /usr/local/libexec).
// Виконує ТІЛЬКИ ці команди, всі аргументи перевіряються:
//   set <fan> <rpm>      ручні оберти (обмежено мін/макс самого вентилятора)
//   auto <fan>           повернути вентилятор у авто
//   auto-all             всі вентилятори в авто
//   prio <pid> <nice>    пріоритет процесу ПОТОЧНОГО користувача (nice -10..20)
//   lowpower <0|1>       Low Power Mode
//   purge                очистити неактивну пам'ять
#include "smc.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>

static int parse_int(const char *s, long lo, long hi, long *out) {
    char *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || !end || *end || v < lo || v > hi) return -1;
    *out = v;
    return 0;
}

static int run(const char *path, char *const argv[]) {
    pid_t p = fork();
    if (p == 0) {
        char *const envp[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL };
        execve(path, argv, envp);
        _exit(127);
    }
    int st = 0;
    if (p < 0 || waitpid(p, &st, 0) < 0) return 1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}

static uid_t owner_of(pid_t pid) {
    struct kinfo_proc kp;
    size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0) return (uid_t)-1;
    return kp.kp_eproc.e_pcred.p_ruid;
}

static int fan_auto(int fan) {
    return smc_fan_set_manual(fan, 0);
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: optimizator-smc set|auto|auto-all|prio|lowpower|purge\n"); return 2; }
    const char *cmd = argv[1];
    long a = 0, b = 0;
    uid_t caller = getuid();          // хто викликав (до підвищення прав)
    if (geteuid() == 0) setuid(0);    // pmset/purge очікують справжній root

    if (!strcmp(cmd, "set") && argc == 4) {
        if (smc_open() != 0) return 3;
        int n = smc_fan_count();
        if (parse_int(argv[2], 0, n - 1, &a) || parse_int(argv[3], 0, 10000, &b)) return 2;
        char k[5]; double mn = 0, mx = 0;
        snprintf(k, sizeof k, "F%ldMn", a); smc_read_number(k, &mn);
        snprintf(k, sizeof k, "F%ldMx", a); smc_read_number(k, &mx);
        double rpm = (double)b;
        if (mn > 0 && rpm < mn) rpm = mn;           // SMC не дозволяє нижче мінімуму
        if (mx > 0 && rpm > mx) rpm = mx;
        if (smc_fan_set_manual((int)a, 1) != 0) return 4;
        return smc_fan_set_target((int)a, rpm) == 0 ? 0 : 5;
    }
    if (!strcmp(cmd, "auto") && argc == 3) {
        if (smc_open() != 0) return 3;
        if (parse_int(argv[2], 0, smc_fan_count() - 1, &a)) return 2;
        return fan_auto((int)a) == 0 ? 0 : 4;
    }
    if (!strcmp(cmd, "auto-all")) {
        if (smc_open() != 0) return 3;
        int n = smc_fan_count(), rc = 0;
        for (int i = 0; i < n; i++) if (fan_auto(i) != 0) rc = 4;
        smc_write_number("Ftst", 0);                 // Apple Silicon: повернути керування системі
        return rc;
    }
    if (!strcmp(cmd, "prio") && argc == 4) {
        if (parse_int(argv[2], 2, 99999999, &a) || parse_int(argv[3], -10, 20, &b)) return 2;
        if (caller != 0 && owner_of((pid_t)a) != caller) return 6;   // лише власні процеси
        return setpriority(PRIO_PROCESS, (id_t)a, (int)b) == 0 ? 0 : 7;
    }
    if (!strcmp(cmd, "lowpower") && argc == 3) {
        if (parse_int(argv[2], 0, 1, &a)) return 2;
        char *const args[] = { "/usr/bin/pmset", "-a", "lowpowermode", a ? "1" : "0", NULL };
        return run("/usr/bin/pmset", args);
    }
    if (!strcmp(cmd, "purge") && argc == 2) {
        char *const args[] = { "/usr/sbin/purge", NULL };
        return run("/usr/sbin/purge", args);
    }
    fprintf(stderr, "unknown command\n");
    return 2;
}
