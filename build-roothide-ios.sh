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

# 完全对齐 TypeX 发布流程：构建成功后先把 deb 归档到 iCloud Downloads/<项目>/<label>/
# （shasum 校验两端一致，旧版本保留），再由 TypeX/webdav-sync.py 增量同步到坚果云
# （鉴权走 ~/.netrc，远端缺失或大小不一致才 PUT，同步后对账，不一致退出码 1）。
# 归档/同步失败只告警并推送 Bark，不影响构建结果与退出码。
WEBDAV_UPLOADED=false
ARCHIVE_FAILED=false

archive_deb_to_icloud() {
    local label="$1"
    local project
    project="$(basename "$ROOT")"
    local deb_path="$ROOT/packages/${label}/${PACKAGE_ID}_${PACKAGE_VERSION}_${label}_iphoneos-arm64e.deb"
    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads/${project}/${label}"
    local icloud_deb="${icloud_dir}/$(basename "$deb_path")"

    if [[ ! -f "$deb_path" ]]; then
        return 0
    fi

    if ! mkdir -p "$icloud_dir" || ! cp -f "$deb_path" "$icloud_deb"; then
        echo "==> [archive] failed to copy deb to iCloud: $icloud_deb" >&2
        ARCHIVE_FAILED=true
        notify_bark "kayokox-${PACKAGE_VERSION}-归档失败"
        return 0
    fi

    local src_sum dst_sum
    src_sum="$(shasum -a 256 "$deb_path" | awk '{print $1}')"
    dst_sum="$(shasum -a 256 "$icloud_deb" | awk '{print $1}')"
    if [[ "$src_sum" != "$dst_sum" ]]; then
        echo "==> [archive] shasum mismatch after iCloud copy: $icloud_deb" >&2
        ARCHIVE_FAILED=true
        notify_bark "kayokox-${PACKAGE_VERSION}-归档失败"
        return 0
    fi

    echo "==> [archive] deb archived to iCloud: $icloud_deb"
}

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
        notify_bark "kayokox编译失败($label)"
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
        notify_bark "kayokox编译失败($label)"
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

notify_bark "kayokox改动完成"

# 归档 iCloud 后由 TypeX/webdav-sync.py 对账同步坚果云（TypeX 流程约定）
for upload_label in ios16 ios17; do
    if [[ "$BUILD_TARGET" != "all" && "$BUILD_TARGET" != "$upload_label" ]]; then
        continue
    fi
    archive_deb_to_icloud "$upload_label"
done

if [[ "$ARCHIVE_FAILED" == false ]]; then
    webdav_sync_script="$(cd "$ROOT/.." && pwd)/TypeX/webdav-sync.py"
    if [[ -f "$webdav_sync_script" ]]; then
        echo "==> [webdav] syncing $(basename "$ROOT") archive to Jianguoyun ..."
        if python3 "$webdav_sync_script" "$(basename "$ROOT")"; then
            WEBDAV_UPLOADED=true
        else
            ARCHIVE_FAILED=true
            notify_bark "kayokox-${PACKAGE_VERSION}-上传失败"
        fi
    else
        echo "==> [webdav] webdav-sync.py not found: $webdav_sync_script, skip" >&2
    fi
fi

if [[ "$ARCHIVE_FAILED" == true ]]; then
    echo "==> [webdav] finished with failures" >&2
elif [[ "$WEBDAV_UPLOADED" == true ]]; then
    notify_bark "kayokox-${PACKAGE_VERSION}-上传完成"
fi
