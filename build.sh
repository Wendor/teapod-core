#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Инструменты (по умолчанию — homebrew; на CI ANDROID_HOME и go из окружения) ──
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/28.2.13676358"
export PATH="/opt/homebrew/bin:$HOME/go/bin:$ANDROID_HOME/platform-tools:$PATH"

GO_BIN="go"
GOMOBILE_BIN="$HOME/go/bin/gomobile"

# ── Общая версия проекта — единственный источник: teapodstream/pubspec.yaml ──
PUBSPEC="$SCRIPT_DIR/../teapodstream/pubspec.yaml"
[[ -f "$PUBSPEC" ]] || { echo "Не найден $PUBSPEC (версия берётся из teapodstream)" >&2; exit 1; }
VERSION=$(awk '/^version:/{split($2,v,"+"); print v[1]; exit}' "$PUBSPEC")
[[ -n "$VERSION" ]] || { echo "Не удалось прочитать version из $PUBSPEC" >&2; exit 1; }

# ── Архитектуры ──────────────────────────────────────────────────────────────
ARCHS=("android/arm64:arm64-v8a" "android/amd64:x86_64")
# Теги sing-box (как в официальной Android-сборке libbox, без лишних сервисов)
TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_naive_outbound,badlinkname,tfogo_checklinkname0"

OUTPUT_DIR="$SCRIPT_DIR/outputs"
mkdir -p "$OUTPUT_DIR"

# ── Rust-ядро: готовый AAR xray-rust-mobile (собран upstream из xray-rust без патчей) ──
XRAY_RUST_VERSION="0.9.0"
XRAY_RUST_SHA256="8f882b5bba982bc0eb44439e1b02eb963299f8929dcfa93ec99246f6c7e78c50"
XRAY_RUST_URL="https://github.com/aimalygin/xray-rust-mobile/releases/download/v${XRAY_RUST_VERSION}/xray-rust-mobile-${XRAY_RUST_VERSION}.aar"
XRAY_RUST_AAR="$SCRIPT_DIR/.native/xray-rust-mobile-${XRAY_RUST_VERSION}.aar"

# ── Цвета ────────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${CYAN}▶ $*${NC}"; }
ok()  { echo -e "${GREEN}✓ $*${NC}"; }
err() { echo -e "${RED}✗ $*${NC}"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────

fetch_xray_rust() {
    mkdir -p "$(dirname "$XRAY_RUST_AAR")"
    if [[ ! -f "$XRAY_RUST_AAR" ]] || [[ "$(shasum -a 256 "$XRAY_RUST_AAR" | cut -d' ' -f1)" != "$XRAY_RUST_SHA256" ]]; then
        log "Downloading xray-rust-mobile $XRAY_RUST_VERSION..."
        curl -fL --progress-bar "$XRAY_RUST_URL" -o "$XRAY_RUST_AAR.download"
        [[ "$(shasum -a 256 "$XRAY_RUST_AAR.download" | cut -d' ' -f1)" == "$XRAY_RUST_SHA256" ]] \
            || { rm -f "$XRAY_RUST_AAR.download"; err "xray-rust-mobile: SHA-256 mismatch"; }
        mv "$XRAY_RUST_AAR.download" "$XRAY_RUST_AAR"
    fi
    ok "xray-rust-mobile $XRAY_RUST_VERSION (sha256 verified)"
}

# Добавляет в распакованный AAR Rust-ядро: .so для наших ABI, классы, proguard-правила.
merge_xray_rust() {
    local dest=$1
    local rust_dir classes_dir
    rust_dir=$(mktemp -d)
    classes_dir=$(mktemp -d)
    unzip -q "$XRAY_RUST_AAR" -d "$rust_dir"
    for entry in "${ARCHS[@]}"; do
        local abi="${entry#*:}"
        mkdir -p "$dest/jni/$abi"
        cp "$rust_dir/jni/$abi/libxray_ffi.so" "$rust_dir/jni/$abi/libxray_mobile_jni.so" "$dest/jni/$abi/"
    done
    (cd "$classes_dir" && unzip -qo "$dest/classes.jar" && unzip -qo "$rust_dir/classes.jar" -x 'META-INF/MANIFEST.MF')
    rm "$dest/classes.jar"
    (cd "$classes_dir" && zip -qr "$dest/classes.jar" .)
    { [[ -f "$dest/proguard.txt" ]] && cat "$dest/proguard.txt"; echo; cat "$rust_dir/proguard.txt"; } > "$dest/proguard.txt.new"
    mv "$dest/proguard.txt.new" "$dest/proguard.txt"
    rm -rf "$rust_dir" "$classes_dir"
}

# xray-core собирается из кэша модулей с патчами patches/xray-core/*.patch
# (go.mod: replace github.com/xtls/xray-core => ./.xray-core).
prepare_xray_core() {
    local version dir dest="$SCRIPT_DIR/.xray-core"
    version=$(awk '$1=="github.com/xtls/xray-core"{print $2; exit}' "$SCRIPT_DIR/go.mod")
    dir=$(cd "$SCRIPT_DIR" && $GO_BIN mod download -json "github.com/xtls/xray-core@$version" | awk -F'"' '$2=="Dir"{print $4}')
    [[ -d "$dir" ]] || err "xray-core $version: модуль не скачан"
    rm -rf "$dest"
    cp -R "$dir" "$dest"
    chmod -R u+w "$dest"
    for p in "$SCRIPT_DIR"/patches/xray-core/*.patch; do
        patch -p1 -s -d "$dest" < "$p" || err "Патч не применился: $(basename "$p")"
    done
    ok "xray-core $version (patched)"
}

build() {
    fetch_xray_rust
    prepare_xray_core
    log "Building teapod-core v$VERSION..."
    # В outputs — только текущая версия: teapodstream берёт AAR строго по версии
    rm -f "$OUTPUT_DIR"/teapod-core-*.aar "$OUTPUT_DIR"/teapod-core-*-sources.jar

    # Версия sing-box задаётся только через -X (иначе "unknown") — берём из go.mod.
    local box_version
    box_version=$(cd "$SCRIPT_DIR" && go list -m -f '{{.Version}}' github.com/sagernet/sing-box)

    for entry in "${ARCHS[@]}"; do
        local target="${entry%%:*}"
        local abi="${entry#*:}"
        local output="$OUTPUT_DIR/teapod-core-${abi}-${VERSION}.aar"

        echo "--------------------------------------------------"
        log "Building $abi ($target)..."

        $GOMOBILE_BIN bind \
            -target="$target" \
            -androidapi=21 \
            -tags="$TAGS" \
            -ldflags="-s -w -checklinkname=0 -X github.com/sagernet/sing-box/constant.Version=${box_version#v}" \
            -trimpath \
            -o "$output" \
            "$SCRIPT_DIR"

        ok "$output"
    done

    echo "--------------------------------------------------"
    log "Building fat AAR (Go + Rust, all ABIs)..."

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

    merge_xray_rust "$tmp_dir"

    rm -f "$fat_aar"
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
        # Тег — на текущий коммит, а не на ветку по умолчанию (master)
        local head
        head=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
        [[ -n "$(git -C "$SCRIPT_DIR" branch -r --contains "$head")" ]] || err "Коммит $head не запушен — сначала git push"
        local flags=("--title" "teapod-core $VERSION" "--generate-notes" "--target" "$head")
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
