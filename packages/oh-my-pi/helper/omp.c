/*
 * omp_helper.c - Glibc bootstrapper for oh-my-pi on Termux
 *
 * Bridges Android Bionic to glibc-linked omp binary.
 * Compile: gcc -static -o omp_helper omp.c          (native)
 *    or:   aarch64-linux-gnu-gcc -static -o omp_helper omp.c  (cross)
 */
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>

#if defined(__x86_64__)
#define LD_LOADER "/data/data/com.termux/files/usr/glibc/lib/ld-linux-x86-64.so.2"
#elif defined(__aarch64__)
#define LD_LOADER "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1"
#else
#error "Unsupported architecture"
#endif

#define LIB_PATH "/data/data/com.termux/files/usr/glibc/lib"
#define BIN_NAME "omp.bin"
#define OMP_LIB "/data/data/com.termux/files/usr/lib/oh-my-pi"

int main(int argc, char **argv) {
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    setenv("SSL_CERT_FILE",
           "/data/data/com.termux/files/usr/etc/tls/cert.pem", 1);
    setenv("TMPDIR",
           "/data/data/com.termux/files/usr/tmp", 1);

    char exec_path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exec_path, sizeof(exec_path) - 1);
    if (len == -1) return 1;
    exec_path[len] = '\0';

    char real_bin[PATH_MAX];
    snprintf(real_bin, sizeof(real_bin), "%s/" BIN_NAME, OMP_LIB);

    char **new_argv = malloc((argc + 4) * sizeof(char *));
    if (!new_argv) return 1;
    new_argv[0] = LD_LOADER;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = real_bin;
    for (int i = 1; i < argc; i++)
        new_argv[i + 3] = argv[i];
    new_argv[argc + 3] = NULL;

    execv(LD_LOADER, new_argv);
    perror("execv");
    free(new_argv);
    return 1;
}
