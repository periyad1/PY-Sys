#!/usr/bin/env bash
# Build PY-Sys.app
#   ./build.sh            → build saja
#   ./build.sh --install  → build + pasang di /Applications + jalankan
#   ./build.sh --dmg      → build + buat installer build/PY-Sys-<versi>.dmg untuk dibagikan ke Mac lain
#   ./build.sh --all      → keduanya: pasang di Mac ini + buat DMG
#
# Opsional (punya akun Apple Developer): set dua variabel ini sebelum --dmg agar
# aplikasi ditandatangani & di-notarize, sehingga terbuka tanpa peringatan di Mac mana pun:
#   export DEV_ID="Developer ID Application: Nama Anda (TEAMID)"
#   export NOTARY_PROFILE="nama-profil-notarytool"
set -euo pipefail
cd "$(dirname "$0")"

# Universal: compile untuk Apple Silicon (arm64) dan Intel (x86_64), lalu gabungkan dengan lipo.
# Pakai "--arm64-only" sebagai argumen kedua untuk build cepat khusus Apple Silicon.
ARCHS=(arm64 x86_64)
[[ "${2:-}" == "--arm64-only" || "${1:-}" == "--arm64-only" ]] && ARCHS=(arm64)
BINS=()
mkdir -p build
for A in "${ARCHS[@]}"; do
    echo "▶ Compile (release, $A)…"
    swift build -c release --arch "$A"
    # Salin segera: SwiftPM baru memakai folder output yang sama untuk semua arsitektur.
    cp "$(swift build -c release --arch "$A" --show-bin-path)/PYSys" "build/PYSys-$A"
    BINS+=("build/PYSys-$A")
done
if [[ ${#BINS[@]} -gt 1 ]]; then
    echo "▶ Menggabungkan menjadi Universal binary…"
    lipo -create "${BINS[@]}" -output build/PYSys-universal
    lipo -info build/PYSys-universal
else
    cp "${BINS[0]}" build/PYSys-universal
fi

APP="build/PY-Sys.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/PYSys-universal "$APP/Contents/MacOS/PYSys"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/donate-qr.png "$APP/Contents/Resources/donate-qr.png"
cp -R Support/Templates "$APP/Contents/Resources/Templates"

if [[ -n "${DEV_ID:-}" ]]; then
    echo "▶ Codesign dengan Developer ID…"
    codesign --force --deep --options runtime --timestamp --sign "$DEV_ID" "$APP"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"PY-Sys Local"'; then
    # Sertifikat lokal tetap → izin Accessibility/Automation tidak hilang setiap build ulang
    echo "▶ Codesign dengan sertifikat lokal \"PY-Sys Local\"…"
    codesign --force --deep --sign "PY-Sys Local" --identifier id.pysys.app "$APP"
else
    echo "▶ Ad-hoc codesign… (jalankan ./make-cert.sh sekali agar izin macOS tidak hilang setiap build)"
    codesign --force --deep --sign - --identifier id.pysys.app "$APP"
fi
echo "✔ Jadi: $APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist 2>/dev/null || echo 1.0)"

do_install() {
    pkill -x AetherMem 2>/dev/null || true
    rm -rf /Applications/AetherMem.app
    pkill -x PYSys 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/PY-Sys.app"
    cp -R "$APP" /Applications/
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    open "/Applications/PY-Sys.app"
    echo "✔ Terpasang di /Applications/PY-Sys.app dan sudah dijalankan."
}

do_dmg() {
    echo "▶ Membuat installer DMG…"
    DMG="build/PY-Sys-$VERSION.dmg"
    STAGE="build/dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp Support/BACA-DULU.txt "$STAGE/" 2>/dev/null || true
    hdiutil create -volname "PY-Sys $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
    rm -rf "$STAGE"
    if [[ -n "${DEV_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
        echo "▶ Notarize (beberapa menit)…"
        codesign --sign "$DEV_ID" --timestamp "$DMG"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    fi
    echo "✔ Installer siap: $(pwd)/$DMG"
    open build
}

case "${1:-}" in
--install) do_install ;;
--dmg) do_dmg ;;
--all) do_install; do_dmg ;;
esac
