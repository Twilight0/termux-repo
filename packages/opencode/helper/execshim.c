// execshim.c - glibc LD_PRELOAD shim for opencode v2 on Termux.
//
// opencode v2 starts its background service by re-executing:
//   [process.execPath, "serve", ...]
// When launched via an explicit glibc loader invocation, process.execPath
// is the loader itself, so the child spawn becomes:
//   ld-linux-aarch64.so.1 serve --service ...
// which fails: the loader cannot open a bare "serve" program (exit 127).
// This shim rewrites such spawns into:
//   ld-linux-aarch64.so.1 $OPENCODE_BIN serve --service ...
// Every other exec passes through untouched.
//
// The shim must not leak into the (bionic) tools opencode spawns, so:
//  - a constructor unsets LD_PRELOAD from this process before the runtime
//    snapshots its environment, and
//  - the rewritten spawn gets a filtered envp without LD_PRELOAD.
//
// Build (glibc-targeting gcc, e.g. TUR gcc-glibc on Termux):
//   aarch64-linux-gnu-gcc -shared -fPIC -O2 -o execshim.so execshim.c
// Use (set by the opencode wrapper, never exported globally):
//   OPENCODE_BIN=/path/to/opencode-bin LD_PRELOAD=/path/to/execshim.so <loader> ...
#define _GNU_SOURCE
#include <dlfcn.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

// Run before main(): drop LD_PRELOAD so child processes spawned later
// (bionic shell tools, MCP servers, ...) start with a clean environment.
// This library itself is already loaded; only future execs are affected.
__attribute__((constructor)) static void drop_preload(void) {
    unsetenv("LD_PRELOAD");
}

static int is_loader(const char *path) {
    const char *b;
    if (!path)
        return 0;
    b = strrchr(path, '/');
    b = b ? b + 1 : path;
    return strcmp(b, "ld-linux-aarch64.so.1") == 0 ||
           strcmp(b, "ld-linux-x86-64.so.2") == 0;
}

static int is_serve_spawn(const char *path, char *const argv[]) {
    return is_loader(path) && argv && argv[0] && argv[1] &&
           strcmp(argv[1], "serve") == 0;
}

// Build a copy of envp without LD_PRELOAD entries. Caller frees.
static char **filtered_env(char *const envp[]) {
    char **out;
    int n = 0, i, j = 0;
    if (!envp)
        return NULL;
    while (envp[n])
        n++;
    out = malloc(sizeof(char *) * (size_t)(n + 1));
    if (!out)
        return NULL;
    for (i = 0; i < n; i++) {
        if (strncmp(envp[i], "LD_PRELOAD=", 11) == 0)
            continue;
        out[j++] = envp[i];
    }
    out[j] = NULL;
    return out;
}

// If this is the opencode service self-spawn, return the rewritten argv
// ([loader, $OPENCODE_BIN, "serve", ...]). Caller frees. NULL otherwise.
static char **fixed_argv(const char *path, char *const argv[]) {
    const char *bin;
    char **out;
    int n = 0, i;
    if (!is_serve_spawn(path, argv))
        return NULL;
    bin = getenv("OPENCODE_BIN");
    if (!bin || !*bin)
        return NULL;
    while (argv[n])
        n++;
    out = malloc(sizeof(char *) * (size_t)(n + 2));
    if (!out)
        return NULL;
    out[0] = argv[0];
    out[1] = (char *)bin;
    for (i = 1; i <= n; i++)
        out[i + 1] = argv[i];
    return out;
}

typedef int (*execve_fn)(const char *, char *const *, char *const *);
typedef int (*spawn_fn)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                        const posix_spawnattr_t *, char *const *, char *const *);

int execve(const char *path, char *const argv[], char *const envp[]) {
    static execve_fn real;
    char **fixed, **env;
    int r;
    if (!real)
        real = (execve_fn)dlsym(RTLD_NEXT, "execve");
    fixed = fixed_argv(path, argv);
    if (!fixed)
        return real(path, argv, envp);
    env = filtered_env(envp);
    r = real(path, fixed, env ? env : envp);
    free(fixed);
    free(env);
    return r;
}

int execvpe(const char *file, char *const argv[], char *const envp[]) {
    static execve_fn real;
    char **fixed, **env;
    int r;
    if (!real)
        real = (execve_fn)dlsym(RTLD_NEXT, "execvpe");
    fixed = fixed_argv(file, argv);
    if (!fixed)
        return real(file, argv, envp);
    env = filtered_env(envp);
    r = real(file, fixed, env ? env : envp);
    free(fixed);
    free(env);
    return r;
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *actions,
                const posix_spawnattr_t *attrp, char *const argv[],
                char *const envp[]) {
    static spawn_fn real;
    char **fixed, **env;
    int r;
    if (!real)
        real = (spawn_fn)dlsym(RTLD_NEXT, "posix_spawn");
    fixed = fixed_argv(path, argv);
    if (!fixed)
        return real(pid, path, actions, attrp, argv, envp);
    env = filtered_env(envp);
    r = real(pid, path, actions, attrp, fixed, env ? env : envp);
    free(fixed);
    free(env);
    return r;
}

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *actions,
                 const posix_spawnattr_t *attrp, char *const argv[],
                 char *const envp[]) {
    static spawn_fn real;
    char **fixed, **env;
    int r;
    if (!real)
        real = (spawn_fn)dlsym(RTLD_NEXT, "posix_spawnp");
    fixed = fixed_argv(file, argv);
    if (!fixed)
        return real(pid, file, actions, attrp, argv, envp);
    env = filtered_env(envp);
    r = real(pid, file, actions, attrp, fixed, env ? env : envp);
    free(fixed);
    free(env);
    return r;
}
