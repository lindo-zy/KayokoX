#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${THEOS:-}" || ! -d "${THEOS:-}" ]]; then
    THEOS="/Users/xiao/dev/theos-roothide"
fi
export THEOS
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

MAKE_BIN="$(command -v gmake || command -v make)"
PACKAGE_ID="$(awk -F': ' '/^Package:/{print $2; exit}' "$ROOT/control")"

if [[ -z "$PACKAGE_ID" || ! "$PACKAGE_ID" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
    echo "error: invalid Debian package name in control: ${PACKAGE_ID:-<missing>}" >&2
    exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [ios16|ios17|all]"
    exit 0
fi

BUILD_TARGET="${1:-all}"
case "$BUILD_TARGET" in
    ios16|ios17|all) ;;
    *)
        echo "Usage: $0 [ios16|ios17|all]" >&2
        exit 1
        ;;
esac

if [[ ! -d "$THEOS" ]]; then
    echo "error: RootHide Theos not found at $THEOS" >&2
    exit 1
fi

CURRENT_PACKAGE_VERSION="$(awk -F':=' '/PACKAGE_VERSION/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$ROOT/Makefile")"
if [[ ! "$CURRENT_PACKAGE_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: unsupported PACKAGE_VERSION: $CURRENT_PACKAGE_VERSION" >&2
    exit 1
fi

VERSION_MAJOR="${BASH_REMATCH[1]}"
VERSION_MINOR="${BASH_REMATCH[2]}"
VERSION_PATCH="${BASH_REMATCH[3]}"
PACKAGE_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}.$((10#$VERSION_PATCH + 1))"

# 版本更新标志，初始为false，构建成功后设为true
VERSION_UPDATED=false

# 更新 Makefile 中的 PACKAGE_VERSION
persist_package_version() {
    # 使用更灵活的匹配方式
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS sed
        sed -i '' "s/^export PACKAGE_VERSION := ${CURRENT_PACKAGE_VERSION}/export PACKAGE_VERSION := ${PACKAGE_VERSION}/" "$ROOT/Makefile"
    else
        # Linux sed
        sed -i "s/^export PACKAGE_VERSION := ${CURRENT_PACKAGE_VERSION}/export PACKAGE_VERSION := ${PACKAGE_VERSION}/" "$ROOT/Makefile"
    fi
    echo "==> Updated Makefile PACKAGE_VERSION: $CURRENT_PACKAGE_VERSION -> $PACKAGE_VERSION"
}

# 更新 control 文件中的 Version 字段
update_control_version() {
    local control_file="$ROOT/control"
    if [[ ! -f "$control_file" ]]; then
        echo "error: control file not found at $control_file" >&2
        exit 1
    fi

    # 检查 control 文件中是否存在 Version 字段
    if ! grep -q "^Version:" "$control_file"; then
        echo "error: Version field not found in control file" >&2
        exit 1
    fi

    # 使用 sed 替代 perl，更可靠
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS sed
        sed -i '' "s/^Version: ${CURRENT_PACKAGE_VERSION}/Version: ${PACKAGE_VERSION}/" "$control_file"
    else
        # Linux sed
        sed -i "s/^Version: ${CURRENT_PACKAGE_VERSION}/Version: ${PACKAGE_VERSION}/" "$control_file"
    fi

    echo "==> Updated control Version: $CURRENT_PACKAGE_VERSION -> $PACKAGE_VERSION"
}

# 回滚 control 文件版本
rollback_control_version() {
    local control_file="$ROOT/control"
    if [[ -f "$control_file" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s/^Version: ${PACKAGE_VERSION}/Version: ${CURRENT_PACKAGE_VERSION}/" "$control_file" 2>/dev/null || true
        else
            sed -i "s/^Version: ${PACKAGE_VERSION}/Version: ${CURRENT_PACKAGE_VERSION}/" "$control_file" 2>/dev/null || true
        fi
        echo "==> Rolled back control Version to $CURRENT_PACKAGE_VERSION"
    fi
}

# 回滚 Makefile 版本
rollback_makefile_version() {
    if [[ -f "$ROOT/Makefile" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s/^export PACKAGE_VERSION := ${PACKAGE_VERSION}/export PACKAGE_VERSION := ${CURRENT_PACKAGE_VERSION}/" "$ROOT/Makefile" 2>/dev/null || true
        else
            sed -i "s/^export PACKAGE_VERSION := ${PACKAGE_VERSION}/export PACKAGE_VERSION := ${CURRENT_PACKAGE_VERSION}/" "$ROOT/Makefile" 2>/dev/null || true
        fi
        echo "==> Rolled back Makefile PACKAGE_VERSION to $CURRENT_PACKAGE_VERSION"
    fi
}

# 检查当前control中的版本是否与目标版本一致
check_control_version() {
    local control_file="$ROOT/control"
    if [[ ! -f "$control_file" ]]; then
        return 1
    fi
    local current_control_version="$(awk -F': ' '/^Version:/{print $2; exit}' "$control_file" 2>/dev/null || echo '')"

    if [[ "$current_control_version" == "$PACKAGE_VERSION" ]]; then
        return 0
    else
        return 1
    fi
}

build_one() {
    local label="$1"
    local sdk_version="$2"
    local deployment_version="$3"
    local sdk_path="$THEOS/sdks/iPhoneOS${sdk_version}.sdk"
    local output_dir="$ROOT/packages/$label"
    local package_path="$ROOT/packages/${PACKAGE_ID}_${PACKAGE_VERSION}_iphoneos-arm64e.deb"
    local output_path="$output_dir/${PACKAGE_ID}_${PACKAGE_VERSION}_${label}_iphoneos-arm64e.deb"

    if [[ ! -d "$sdk_path" ]]; then
        echo "error: required SDK not found: $sdk_path" >&2
        exit 1
    fi

    echo "==> Building RootHide package for $label with iPhoneOS${sdk_version}.sdk"

    # 执行构建，如果失败则退出
    if ! "$MAKE_BIN" clean >/dev/null 2>&1; then
        echo "error: make clean failed" >&2
        exit 1
    fi

    if ! THEOS_PACKAGE_SCHEME=roothide \
        TARGET="iphone:clang:${sdk_version}:${deployment_version}" \
        "$MAKE_BIN" package FINALPACKAGE=1 PACKAGE_VERSION="$PACKAGE_VERSION"; then
        echo "error: build failed for $label" >&2
        exit 1
    fi

    # 创建目标文件夹
    mkdir -p "$output_dir"

    # 清理目标文件夹中已有的旧版本deb文件（保留文件夹）
    if [[ -d "$output_dir" ]]; then
        find "$output_dir" -maxdepth 1 -type f -name "*.deb" -delete 2>/dev/null || true
    fi

    # 将生成的deb文件移动到对应的ios版本文件夹
    if [[ -f "$package_path" ]]; then
        mv "$package_path" "$output_path"
        echo "==> Output: $output_path"
    else
        echo "error: package not found at $package_path" >&2
        exit 1
    fi

    # 清理根目录packages下可能残留的deb文件（保留文件夹）
    if [[ -d "$ROOT/packages" ]]; then
        find "$ROOT/packages" -maxdepth 1 -type f -name "*.deb" -delete 2>/dev/null || true
    fi

    # 标记版本已更新
    VERSION_UPDATED=true
}

cleanup_debs() {
    # 确保packages根目录下没有deb文件
    if [[ -d "$ROOT/packages" ]]; then
        find "$ROOT/packages" -maxdepth 1 -type f -name "*.deb" -delete 2>/dev/null || true
    fi

    # 确保ios16和ios17文件夹下各自只保留自己版本的deb文件
    for subdir in ios16 ios17; do
        local subdir_path="$ROOT/packages/$subdir"
        if [[ -d "$subdir_path" ]]; then
            # 删除不匹配该文件夹名称的deb文件
            find "$subdir_path" -maxdepth 1 -type f -name "*.deb" ! -name "*_${subdir}_*" -delete 2>/dev/null || true
        fi
    done
}

# 清理函数，用于构建失败时恢复
cleanup_on_failure() {
    echo "==> Build failed, rolling back version changes..."

    # 如果已经更新了版本，尝试回滚
    if [[ "$VERSION_UPDATED" == true ]]; then
        rollback_control_version
        rollback_makefile_version
    fi
}

# 设置错误处理陷阱
trap cleanup_on_failure ERR

echo "==> New package version will be: $PACKAGE_VERSION"
echo "==> Current control version: $(awk -F': ' '/^Version:/{print $2; exit}' "$ROOT/control" 2>/dev/null || echo 'unknown')"

# 检查当前control版本是否已经是最新
if check_control_version; then
    echo "==> control file already at version $PACKAGE_VERSION"
else
    # 更新 control 文件的 Version 字段
    update_control_version
fi

# 清理可能存在的旧deb文件
cleanup_debs

# 执行构建
case "$BUILD_TARGET" in
    ios16)
        build_one ios16 16.5 16.0
        ;;
    ios17)
        build_one ios17 17.0 17.0
        ;;
    all)
        build_one ios16 16.5 16.0
        build_one ios17 17.0 17.0
        ;;
esac

# 最终清理，确保packages根目录没有deb文件
cleanup_debs

# 只有在构建成功时才更新 Makefile
if [[ "$VERSION_UPDATED" == true ]]; then
    # 检查Makefile是否已经更新到新版本
    current_makefile_version="$(awk -F':=' '/PACKAGE_VERSION/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$ROOT/Makefile" 2>/dev/null || echo '')"
    if [[ "$current_makefile_version" != "$PACKAGE_VERSION" ]]; then
        persist_package_version
    else
        echo "==> Makefile PACKAGE_VERSION already at $PACKAGE_VERSION"
    fi
fi

echo "==> Build completed successfully!"
echo "==> Final version: $PACKAGE_VERSION"
echo "==> Cleanup complete: deb files only in ios16/ios17 folders"
