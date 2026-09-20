/*
 * agy_helper.c - Glibc bootstrapper for Antigravity CLI on Termux
 *
 * Bridges Android Bionic to glibc-linked agy binary.
 * Usage: agy_helper <binary_name> [args...]
 * Compile: gcc -static -o agy_helper agy.c
 *    or:   aarch64-linux-gnu-gcc -static -o agy_helper agy.c
 */
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
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
#define AGY_LIB "/data/data/com.termux/files/usr/lib/antigravity-cli"

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <binary_name> [args...]\n", argv[0]);
        return 1;
    }

    const char *bin_name = argv[1];

    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    setenv("GODEBUG", "netdns=cgo", 1);
    setenv("SSL_CERT_FILE",
           "/data/data/com.termux/files/usr/etc/tls/cert.pem", 1);

    char real_bin[PATH_MAX];
    snprintf(real_bin, sizeof(real_bin), "%s/%s.bin", AGY_LIB, bin_name);

    char **new_argv = malloc((argc + 3) * sizeof(char *));
    if (!new_argv) return 1;
    new_argv[0] = LD_LOADER;
    new_argv[1] = "--library-path";
    new_argv[2] = LIB_PATH;
    new_argv[3] = real_bin;
    for (int i = 2; i < argc; i++)
        new_argv[i + 2] = argv[i];
    new_argv[argc + 2] = NULL;

    execv(LD_LOADER, new_argv);
    perror("execv");
    free(new_argv);
    return 1;
}
