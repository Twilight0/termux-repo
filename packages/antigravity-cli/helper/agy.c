/*
 * agy_helper.c - Glibc bootstrapper for Antigravity CLI on Termux
 *
 * Bridges Android Bionic to glibc-linked agy binary.
 * Cross-compile: aarch64-linux-gnu-gcc -static -o agy_helper agy.c
 */
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>

int main(int argc, char **argv) {
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    setenv("GODEBUG", "netdns=cgo", 1);
    setenv("SSL_CERT_FILE",
           "/data/data/com.termux/files/usr/etc/tls/cert.pem", 1);

    char exec_path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exec_path, sizeof(exec_path) - 1);
    if (len == -1) return 1;
    exec_path[len] = '\0';

    char *loader    = "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1";
    char lib_path[] = "/data/data/com.termux/files/usr/glibc/lib";

    char *dir = dirname(exec_path);
    char real_bin[PATH_MAX];
    snprintf(real_bin, sizeof(real_bin), "%s/agy.bin", dir);

    char **new_argv = malloc((argc + 4) * sizeof(char *));
    if (!new_argv) return 1;
    new_argv[0] = loader;
    new_argv[1] = "--library-path";
    new_argv[2] = lib_path;
    new_argv[3] = real_bin;
    for (int i = 1; i < argc; i++)
        new_argv[i + 3] = argv[i];
    new_argv[argc + 3] = NULL;

    execv(loader, new_argv);
    perror("execv");
    free(new_argv);
    return 1;
}
