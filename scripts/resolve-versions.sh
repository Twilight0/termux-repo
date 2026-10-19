#!/usr/bin/env bash
# Resolve every package's upstream version at build time so CI always
# tracks the latest release, not the pinned defaults in the packages.
#
# Usage:  bash scripts/resolve-versions.sh <github-env-file>
#         (CI passes "$GITHUB_ENV"; locally it defaults to /dev/null)
#
# Output: one VAR=value line per package, exported into the given file.
# Any explicit environment override already set by the caller is kept
# (exported again) and never overwritten, so local builds can pin.
set -euo pipefail

ENVFILE="${1:-/dev/null}"
: > "$ENVFILE"

# Emit VAR=value, and also to stdout for logging. Skips if the caller
# already set VAR (that value wins — keeps manual overrides possible).
export_var() {
    local var="$1" val="$2"
    if [ -z "$val" ]; then
        echo "resolve-versions: WARN: empty value for $var, keeping existing/default" >&2
        return 0
    fi
    printf '%s=%s\n' "$var" "$val" >> "$ENVFILE"
    # Only caller-provided environment counts as an override (printenv,
    # not ${!var}, so in-function temporaries don't shadow it).
    if [ -n "$(printenv "$var" 2>/dev/null || true)" ]; then
        echo "resolve-versions: $var=${!var} (env override wins)"
    else
        echo "resolve-versions: $var=$val"
        export "$var=$val"
    fi
}

http_get() {
    # Extra leading args pass through to curl; the last arg is the URL.
    local out="" url="${*: -1}" extra=("${@:1:$#-1}")
    for _ in 1 2 3; do
        if out="$(curl -sSL -H 'Accept: application/vnd.github+json' "${extra[@]}" "$url")"; then
            printf '%s' "$out"
            return 0
        fi
        sleep 2
    done
    return 1
}

# Latest tag of a GitHub repo (releases endpoint).
latest_release() {
    http_get "https://api.github.com/repos/$1/releases/latest" \
        | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
t=d.get("tag_name","") if isinstance(d,dict) else ""
print(t.lstrip("v") if t else "")' || true
}

# Latest PyPI version.
pypi_latest() {
    http_get "https://pypi.org/pypi/$1/json" \
        | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
try: print(d["info"].get("version",""))
except Exception: print("")' || true
}

echo "=== Resolving upstream versions ==="

# --- curl-cffi: Android wheels come from Twilight0/curl-cffi-builder
#     release tags (v0.16.3). Prefer PyPI's stable version when the
#     builder offers it; otherwise fall back to the builder's newest. ---
CCWB="$(latest_release Twilight0/curl-cffi-builder)"   # e.g. 0.16.4b1
if [ -z "$CCWB" ]; then
    # Builder tag unknown (upstream hiccup): keep the package defaults.
    echo "resolve-versions: WARN: curl-cffi builder fetch failed, keeping defaults" >&2
else
    CCVER="$(pypi_latest curl-cffi)"
    CC_TAG=""
    if [ -n "$CCVER" ]; then
        # Check the builder has a release for this stable PyPI version.
        if [ "$(http_get "https://api.github.com/repos/Twilight0/curl-cffi-builder/releases?per_page=50" \
            | python3 -c '
import json,sys
try: rels=json.load(sys.stdin)
except Exception: rels=[]
want="v"+sys.argv[1]
cc=0
if rels and isinstance(rels,list):
    cc=1 if any(isinstance(r,dict) and r.get("tag_name")==want for r in rels) else 0
print(cc)' "$CCVER")" = "1" ]; then
            CCWB="$CCVER"
            CC_TAG="v$CCVER"
        else
            CC_TAG="v$CCWB"
        fi
    elif [ -n "$CCWB" ]; then
        CC_TAG="v$CCWB"
    fi
    export_var CURL_CFFI_VERSION "${CCWB%%b*}"
    export_var CURL_CFFI_TAG     "$CC_TAG"
fi

# --- agentty: latest release of 1ay1/agentty (also drives the source checkout ref) ---
export_var AGENTTY_VERSION "$(latest_release 1ay1/agentty)"

# --- opencode (v2): binaries only on opencode.ai, no version feed. Probe
#     upward from the repo's fallback until the URL 404s. ---
OC_BASE="${OPENCODE_VERSION:-$(grep -m1 'OPENCODE_VERSION:-' packages/opencode/build.sh \
    | sed 's/.*:-\([0-9.]*\).*/\1/')}"   # e.g. 2.0.29
OC_BEST="$OC_BASE"
# HEAD request: 200 = a binary exists on opencode.ai for that version.
probe_version() {
    [ "$(curl -sI -o /dev/null -w '%{http_code}' -m 30 \
        "https://opencode.ai/files/bin/$1/opencode-linux-arm64.tar.gz")" = "200" ]
}
# Probe a tripart version from the repo's fallback upward while the CDN
# serves it. Old versions stay 200, so simply walking ascending triple
# order is safe: patch within the fallback's minor, then minor lines,
# then (at most two) major lines.
OC_MAJOR="${OC_BASE%%.*}"; OC_REST="${OC_BASE#*.}"
OC_MINOR="${OC_REST%%.*}"; OC_PATCH="${OC_REST#*.}"

# Walk the fallback minor line's patches.
for q in $(seq $((OC_PATCH+1)) $((OC_PATCH+30))); do
    probe_version "$OC_MAJOR.$OC_MINOR.$q" || break
    OC_BEST="$OC_MAJOR.$OC_MINOR.$q"
done
# A line "x.y" exists if a first release actually serves: x.y.0 OR x.y.1
# (opencode has shipped .0-only and .1-only second versions).
line_exists() {
    probe_version "$1.0" || probe_version "$1.1" || return 1
}

# Walk subsequent minor lines ("x.y.1" upward since base patch count differs).
for m in $(seq $((OC_MINOR+1)) $((OC_MINOR+15))); do
    line="$OC_MAJOR.$m"
    line_exists "$line" || break
    for q in 0 $(seq 1 30); do
        # .0 is confirmed by line_exists only when q=0 has no patches... walk anyway
        probe_version "$line.$q" || break
        OC_BEST="$line.$q"
    done
done
# Walk up to two later major lines.
for _major in $((OC_MAJOR+1)) $((OC_MAJOR+2)); do
    line0="$_major.0"
    line_exists "$line0" || break
    for q in 0 $(seq 1 30); do
        probe_version "$line0.$q" || break
        OC_BEST="$line0.$q"
    done
    # Also subsequent minors of the new major.
    for m in $(seq 1 15); do
        line="$_major.$m"
        line_exists "$line" || break
        for q in 0 $(seq 1 30); do
            probe_version "$line.$q" || break
            OC_BEST="$line.$q"
        done
    done
done
export_var OPENCODE_VERSION "$OC_BEST"

# --- oh-my-pi ---
export_var OMP_VERSION "$(latest_release can1357/oh-my-pi)"

# --- copilot-cli: latest release of github/copilot-cli ---
export_var COPILOT_CLI_VERSION "$(latest_release github/copilot-cli)"

# --- muse-code: Meta's channel manifest gives version AND sha256 sums ---
MUSE_DOC="$(http_get https://api.meta.ai/muse-code/channels/muse-stable || true)"
MUSE_REALVER="$(printf '%s' "$MUSE_DOC" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("version",""))' || true)"
export_var MUSE_REALVER "$MUSE_REALVER"
if [ -n "$MUSE_REALVER" ]; then
    export_var MUSE_PKGVER "$(printf '%s' "$MUSE_REALVER" | tr R- 'r.')"
fi
MUSE_MANIFEST="$(http_get "https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=${MUSE_REALVER}&file=manifest.json" || true)"
export_var MUSE_SHA256_AARCH64 "$(printf '%s' "$MUSE_MANIFEST" | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifacts"]["aarch64_linux"]["checksum"])' || true)"
export_var MUSE_SHA256_X86_64  "$(printf '%s' "$MUSE_MANIFEST" | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifacts"]["x86_linux"]["checksum"])' || true)"

echo "=== Done ==="
