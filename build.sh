#!/bin/bash
#
# Kayoko package builder.
#
# Building and packaging are handled by Theos. Each scheme needs a separately
# compiled binary because install names and path bases differ between schemes.
#
# Usage:
#   ./build.sh roothide
#   ./build.sh rootless
#   ./build.sh rootful
#
# Optional environment overrides:
#   THEOS=/path/to/theos       # otherwise auto-detected
#
# Output debs land in ./packages/. The architecture suffix distinguishes variants.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Keep common package-manager paths available in minimal shells.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# --- Resolve Theos -----------------------------------------------------------
if [[ -z "${THEOS:-}" || ! -d "${THEOS:-}" ]]; then
    for candidate in "${HOME}/theos" /opt/theos "${HOME}/theos-roothide"; do
        if [[ -d "$candidate" ]]; then
            THEOS="$candidate"
            break
        fi
    done
fi
if [[ -z "${THEOS:-}" || ! -d "$THEOS" ]]; then
    echo "error: no Theos install found; set THEOS to your Theos path" >&2
    exit 1
fi
export THEOS

MAKE_BIN="$(command -v gmake || command -v make)"
PACKAGE_ID="$(awk -F': ' '/^Package:/{print $2; exit}' "$ROOT/control")"

# 编译结果 Bark 推送；key 保存在本地 local.env（已 gitignore，不入库）。
# 推送失败只告警，不影响编译结果与退出码。
notify_bark() {
    local message="$1"
    local env_file="$ROOT/local.env"

    if [[ ! -f "$env_file" ]]; then
        echo "==> [bark] $env_file not found, skip push" >&2
        return 0
    fi
    # shellcheck disable=SC1090
    if ! source "$env_file"; then
        echo "==> [bark] failed to load $env_file, skip push" >&2
        return 0
    fi
    if [[ -z "${BARK_KEY:-}" ]]; then
        echo "==> [bark] BARK_KEY not set in $env_file, skip push" >&2
        return 0
    fi

    local encoded="$message"
    if command -v python3 >/dev/null 2>&1; then
        encoded="$(python3 -c 'import sys, urllib.parse; sys.stdout.write(urllib.parse.quote(sys.argv[1], safe=""))' "$message")"
    fi

    if curl -fsS --max-time 10 "https://api.day.app/${BARK_KEY}/${encoded}" >/dev/null 2>&1; then
        echo "==> [bark] push sent: $message"
    else
        echo "==> [bark] push failed, build result unaffected" >&2
    fi
    return 0
}

cleanup_build_artifacts() {
    echo ""
    echo "==> Cleaning build cache…"
    "$MAKE_BIN" clean >/dev/null 2>&1 || true

    while IFS= read -r -d '' cache_dir; do
        rm -rf "$cache_dir"
    done < <(find "$ROOT" -type d -name .theos -prune -print0)

    find "$ROOT" -type f \( \
        -name '.DS_Store' -o \
        -name '*.o' -o \
        -name '*.Td' -o \
        -name '*.stamp' -o \
        -name '*.xcuserstate' \
    \) -delete 2>/dev/null || true
}

# --- Build one scheme --------------------------------------------------------
# Theos writes the deb as <package>_<version>_<arch>.deb. The selected package
# scheme controls the installation layout; CPU architectures remain defined by
# the root Makefile.
# theos_scheme: value passed to THEOS_PACKAGE_SCHEME ("" for rootful)
build_one() {
    local label="$1"
    local theos_scheme="$2"

    echo ""
    echo "==> Building ${label} package (THEOS=${THEOS})…"

    THEOS_PACKAGE_SCHEME="$theos_scheme" "$MAKE_BIN" clean >/dev/null 2>&1 || true
    THEOS_PACKAGE_SCHEME="$theos_scheme" "$MAKE_BIN" package FINALPACKAGE=1
}

# --- Dispatch ----------------------------------------------------------------
scheme="${1:-}"
case "$scheme" in
    -h|--help|help)
        echo "Usage: ./build.sh [roothide|rootless|rootful]"
        exit 0
        ;;
    roothide|rootless|rootful) ;;
    *)
        echo "error: unknown scheme '$scheme'" >&2
        echo "Usage: ./build.sh [roothide|rootless|rootful]" >&2
        exit 1
        ;;
esac

# 编译开始后才推送结果；--help 或参数错误不推送
BUILD_STARTED=false

finalize() {
    local rc=$?
    cleanup_build_artifacts
    if [[ "$BUILD_STARTED" == true ]]; then
        if [[ "$rc" -eq 0 ]]; then
            notify_bark "kayokox改动完成"
        else
            notify_bark "kayokox编译失败"
        fi
    fi
}

trap finalize EXIT

BUILD_STARTED=true

case "$scheme" in
    roothide) build_one roothide roothide ;;
    rootless) build_one rootless rootless ;;
    rootful)  build_one rootful  ""       ;;
esac

echo ""
echo "==> Done. Packages in ./packages/:"
ls -1 "$ROOT/packages/${PACKAGE_ID}_"*.deb 2>/dev/null || true
