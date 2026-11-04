#!/bin/bash
set -euo pipefail
THREADLIGHT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$THREADLIGHT_ROOT"
case "${1:-}" in
    "") ./scripts/build-app.sh ;;
    --skip-build) ;;
    *) echo "Usage: $0 [--skip-build]" >&2; exit 2 ;;
esac
THREADLIGHT_APP="$THREADLIGHT_ROOT/build/Threadlight.app"
test -x "$THREADLIGHT_APP/Contents/MacOS/Threadlight"
codesign --verify --deep --strict "$THREADLIGHT_APP"
"$THREADLIGHT_APP/Contents/MacOS/Threadlight" --check-assets
THREADLIGHT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$THREADLIGHT_APP/Contents/Info.plist")"
THREADLIGHT_ARCH="$(lipo -archs "$THREADLIGHT_APP/Contents/MacOS/Threadlight" | tr ' ' '-')"
THREADLIGHT_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/threadlight-dmg.XXXXXX")"
THREADLIGHT_MOUNT="$THREADLIGHT_STAGE/verify"
THREADLIGHT_ATTACHED=0
detach_verification_image() {
    # Spotlight can briefly hold the just-mounted image. This is our own
    # read-only verification volume, so forcing its final detach cannot lose writes.
    for attempt in 1 2 3; do
        if hdiutil detach "$THREADLIGHT_MOUNT" >/dev/null 2>&1; then return 0; fi
        sleep 1
    done
    hdiutil detach -force "$THREADLIGHT_MOUNT" >/dev/null
}
cleanup() {
    if [[ "$THREADLIGHT_ATTACHED" == 1 ]]; then
        detach_verification_image || return
    fi
    rm -rf "$THREADLIGHT_STAGE"
}
trap cleanup EXIT
mkdir -p "$THREADLIGHT_STAGE/content" "$THREADLIGHT_MOUNT" dist
ditto "$THREADLIGHT_APP" "$THREADLIGHT_STAGE/content/Threadlight.app"
ln -s /Applications "$THREADLIGHT_STAGE/content/应用程序"
cat > "$THREADLIGHT_STAGE/content/安装说明.txt" <<'INSTRUCTIONS'
Threadlight · 对话灯

1. 将 Threadlight.app 拖到旁边的“应用程序”文件夹。
2. 从“应用程序”打开“对话灯”。图标会出现在顶部菜单栏，默认显示置顶任务列表。
3. 安装后可推出这个磁盘镜像；不要长期从镜像中运行应用。

更新前请从旧版的菜单中选择“退出对话灯”，再拖动替换。

本应用不需要输入 API Key，不会发送网络请求，也不会修改 Codex 或 Claude 的设置。
INSTRUCTIONS
codesign --verify --deep --strict "$THREADLIGHT_STAGE/content/Threadlight.app"
hdiutil create -quiet -format UDZO -fs HFS+ -volname "Threadlight 对话灯" \
    -srcfolder "$THREADLIGHT_STAGE/content" "$THREADLIGHT_STAGE/Threadlight.dmg"
hdiutil verify "$THREADLIGHT_STAGE/Threadlight.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$THREADLIGHT_MOUNT" \
    -plist "$THREADLIGHT_STAGE/Threadlight.dmg" > "$THREADLIGHT_STAGE/mount.plist"
THREADLIGHT_ATTACHED=1
test "$(readlink "$THREADLIGHT_MOUNT/应用程序")" == /Applications
codesign --verify --deep --strict "$THREADLIGHT_MOUNT/Threadlight.app"
"$THREADLIGHT_MOUNT/Threadlight.app/Contents/MacOS/Threadlight" --check-assets
cmp "$THREADLIGHT_APP/Contents/MacOS/Threadlight" "$THREADLIGHT_MOUNT/Threadlight.app/Contents/MacOS/Threadlight"
detach_verification_image
THREADLIGHT_ATTACHED=0
THREADLIGHT_OUTPUT="$THREADLIGHT_ROOT/dist/Threadlight-$THREADLIGHT_VERSION-macOS-$THREADLIGHT_ARCH.dmg"
mv "$THREADLIGHT_STAGE/Threadlight.dmg" "$THREADLIGHT_OUTPUT"
echo "DMG verified: $THREADLIGHT_OUTPUT"
