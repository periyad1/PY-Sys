#!/usr/bin/env bash
# Rilis versi baru PY-Sys ke GitHub dalam satu perintah:
#   ./release.sh "Catatan perubahan versi ini"
# Langkah: build universal + DMG → commit & push kode → buat GitHub Release berisi DMG.
# Pengguna PY-Sys (versi 1.5.2+) akan melihat banner "Perbarui sekarang" paling lambat dalam sehari.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
NOTES="${1:-PY-Sys $VERSION}"
TAG="v$VERSION"
DMG="build/PY-Sys-${VERSION}.dmg"

command -v gh >/dev/null || { echo "✖ GitHub CLI belum terpasang: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✖ Belum login GitHub: gh auth login"; exit 1; }
# File .github/workflows hanya bisa di-push bila token gh punya izin "workflow".
if [[ -d .github/workflows ]]; then
    SCOPES="$(gh auth status 2>&1 || true)"
    if [[ "${SCOPES}" != *workflow* ]]; then
        echo "→ Menambah izin 'workflow' ke login GitHub (sekali saja, browser akan terbuka)…"
        gh auth refresh -h github.com -s workflow
    fi
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "✖ Rilis ${TAG} sudah ada di GitHub. Naikkan versi di Support/Info.plist dulu."
    exit 1
fi

echo "▶ Build PY-Sys ${VERSION}…"
./build.sh --dmg
[[ -f "$DMG" ]] || { echo "✖ ${DMG} tidak ditemukan"; exit 1; }

# Rilis wajib bertanda tangan "PY-Sys Local": PY-Sys di Mac pengguna menolak pembaruan dengan tanda tangan lain.
SIG="$(codesign -dvv build/PY-Sys.app 2>&1 || true)"
if [[ "${SIG}" != *"Authority=PY-Sys Local"* ]]; then
    echo "✖ build/PY-Sys.app tidak ditandatangani sertifikat \"PY-Sys Local\"."
    echo "  Jalankan ./make-cert.sh (atau impor cadangan sertifikat), lalu ulangi ./release.sh."
    exit 1
fi

if [[ ! -d .git ]]; then
    echo "▶ Membuat repo GitHub PY-Sys (public)…"
    git init -q
    git add -A
    git commit -qm "PY-Sys $VERSION"
    gh repo create PY-Sys --public --source=. --push
else
    git add -A
    git commit -qm "PY-Sys $VERSION" || echo "  (tidak ada perubahan kode untuk di-commit)"
    git push -q
fi

echo "▶ Membuat GitHub Release ${TAG}…"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
FULL_NOTES="${NOTES}

---
**SHA-256** \`PY-Sys-${VERSION}.dmg\`: \`${SHA}\`
Cek keaslian setelah mengunduh: \`shasum -a 256 ~/Downloads/PY-Sys-${VERSION}.dmg\` (hasilnya harus sama persis)."
gh release create "$TAG" "$DMG" --title "PY-Sys $VERSION" --notes "$FULL_NOTES"

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "✔ Rilis selesai: https://github.com/${REPO}/releases/tag/$TAG"
echo "  Isi \"${REPO}\" di PY-Sys → Pengaturan → Pembaruan (sekali saja)."
