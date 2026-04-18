#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Инструменты ──────────────────────────────────────────────────────────────
GO_BIN="/opt/homebrew/bin/go"
GOMOBILE_BIN="/Users/wendor/go/bin/gomobile"

export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_NDK_HOME="/opt/homebrew/share/android-commandlinetools/ndk/28.2.13676358"
export PATH="/opt/homebrew/bin:/Users/wendor/go/bin:$ANDROID_HOME/platform-tools:$PATH"

# ── Версия из teapod-tun2socks/kotlin/gradle.properties ──────────────────────
TUN2SOCKS_PROPS="$SCRIPT_DIR/../teapod-tun2socks/kotlin/gradle.properties"
if [[ -f "$TUN2SOCKS_PROPS" ]]; then
    VERSION=$(grep "^libraryVersion" "$TUN2SOCKS_PROPS" | cut -d'=' -f2 | tr -d ' \r\n')
fi
VERSION="${VERSION:-1.0.0}"

# ── Архитектуры ──────────────────────────────────────────────────────────────
ARCHS=("android/arm:armeabi-v7a" "android/arm64:arm64-v8a" "android/amd64:x86_64")

OUTPUT_DIR="$SCRIPT_DIR/outputs"
mkdir -p "$OUTPUT_DIR"

# ── Цвета ────────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${CYAN}▶ $*${NC}"; }
ok()  { echo -e "${GREEN}✓ $*${NC}"; }
err() { echo -e "${RED}✗ $*${NC}"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────

build() {
    log "Building teapod-core v$VERSION..."

    for entry in "${ARCHS[@]}"; do
        local target="${entry%%:*}"
        local abi="${entry#*:}"
        local output="$OUTPUT_DIR/teapod-core-${abi}-${VERSION}.aar"

        echo "--------------------------------------------------"
        log "Building $abi ($target)..."

        $GOMOBILE_BIN bind \
            -target="$target" \
            -androidapi=21 \
            -ldflags='-s -w' \
            -trimpath \
            -o "$output" \
            "$SCRIPT_DIR"

        ok "$output"
    done

    echo "--------------------------------------------------"
    log "Building fat AAR (all ABIs)..."

    local fat_aar="$OUTPUT_DIR/teapod-core-${VERSION}.aar"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local base_set=0

    for entry in "${ARCHS[@]}"; do
        local abi="${entry#*:}"
        local src="$OUTPUT_DIR/teapod-core-${abi}-${VERSION}.aar"
        if [[ $base_set -eq 0 ]]; then
            unzip -q "$src" -d "$tmp_dir"
            base_set=1
        else
            mkdir -p "$tmp_dir/jni/$abi"
            unzip -p "$src" "jni/$abi/libgojni.so" > "$tmp_dir/jni/$abi/libgojni.so"
        fi
    done

    (cd "$tmp_dir" && zip -r "$fat_aar" . -x "*.DS_Store" -q)
    rm -rf "$tmp_dir"

    echo "--------------------------------------------------"
    ok "Build complete! v$VERSION"
    ls -lh "$OUTPUT_DIR"/teapod-core-*-${VERSION}.aar
    echo ""
    ok "Fat AAR: $fat_aar ($(du -sh "$fat_aar" | cut -f1))"
}

push() {
    local is_pre="${1:-false}"
    local tag="v$VERSION"
    local fat_aar="$OUTPUT_DIR/teapod-core-${VERSION}.aar"

    # Проверяем наличие артефактов
    if [[ ! -f "$fat_aar" ]]; then
        err "Fat AAR не найден: $fat_aar. Сначала выполните: ./build.sh build"
    fi

    local per_abi_aars=()
    for entry in "${ARCHS[@]}"; do
        local abi="${entry#*:}"
        local f="$OUTPUT_DIR/teapod-core-${abi}-${VERSION}.aar"
        [[ -f "$f" ]] && per_abi_aars+=("$f")
    done

    # Проверяем gh
    command -v gh &>/dev/null || err "gh CLI не найден. Установите: brew install gh && gh auth login"
    gh auth status &>/dev/null || err "Не авторизован. Выполните: gh auth login"

    log "Публикация релиза $tag..."

    local assets=("$fat_aar" "${per_abi_aars[@]}")

    if gh release view "$tag" &>/dev/null; then
        log "Релиз $tag уже существует, обновляю assets..."
        gh release upload "$tag" "${assets[@]}" --clobber
    else
        local flags=("--title" "teapod-core $VERSION" "--generate-notes")
        [[ "$is_pre" == "true" ]] && flags+=("--prerelease")
        gh release create "$tag" "${flags[@]}" "${assets[@]}"
    fi

    ok "Релиз $tag опубликован!"
}

# ── Точка входа ──────────────────────────────────────────────────────────────
case "${1:-build}" in
    build)
        build
        ;;
    push)
        push false
        ;;
    pushpre)
        push true
        ;;
    help|--help|-h|*)
        echo ""
        echo "  teapod-core build script  (v$VERSION)"
        echo ""
        echo "  Команды:"
        echo "    ./build.sh build    Собрать все ABI + fat AAR"
        echo "    ./build.sh push     Опубликовать релиз на GitHub"
        echo "    ./build.sh pushpre  Опубликовать pre-release на GitHub"
        echo ""
        ;;
esac
