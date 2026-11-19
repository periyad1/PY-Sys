#!/usr/bin/env bash
# Rilis PY-Sys ke GitHub. Perbaikan kecil dikumpulkan dulu, lalu dirilis bersama:
#   ./release.sh --simpan "catatan"   → catat di CATATAN-RILIS.md ("Belum dirilis"), commit & push kode saja
#   ./release.sh ["catatan tambahan"] → build universal + DMG → commit & push → GitHub Release
#                                       berisi semua catatan "Belum dirilis"
# Pengguna PY-Sys (versi 1.5.2+) akan melihat banner "Perbarui sekarang" paling lambat dalam sehari.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
LOG="CATATAN-RILIS.md"
[[ -f "$LOG" ]] || printf '# Catatan rilis PY-Sys\n\n## Belum dirilis\n\n' > "$LOG"

pending() { awk '/^## Belum dirilis/{f=1;next} /^## /{f=0} f && /^- /' "$LOG"; }
# Sisipkan teks tepat di bawah judul "## Belum dirilis" (awk bawaan macOS).
under_pending() {
    awk -v txt="$1" 'skip && /^$/ {skip=0; next} {skip=0; print} /^## Belum dirilis/{print ""; n=split(txt, a, "\n"); for (i=1;i<=n;i++) print a[i]; skip=1}' "$LOG" > "$LOG.tmp"
    mv "$LOG.tmp" "$LOG"
}

# ---- Mode simpan: kode masuk GitHub (dicek Actions), pengguna belum diberi notifikasi ----
if [[ "${1:-}" == "--simpan" ]]; then
    MSG="${2:-}"
    [[ -n "$MSG" ]] || { echo "✖ Tulis catatannya: ./release.sh --simpan \"Perbaiki ...\""; exit 1; }
    [[ -d .git ]] || { echo "✖ Folder ini belum repo git. Jalankan ./release.sh biasa sekali dulu."; exit 1; }
    under_pending "- ${MSG}"
    git add -A
    git commit -qm "$MSG" || echo "  (tidak ada perubahan kode untuk di-commit)"
    git push -q
    echo "✔ Disimpan ke GitHub (belum dirilis). Catatan yang menunggu rilis:"
    pending
    echo "  Rilis semuanya nanti dengan: ./release.sh"
    exit 0
fi

PEND="$(pending)"
NOTES="${PEND}"
if [[ -n "${1:-}" ]]; then NOTES="${NOTES:+${NOTES}
}- ${1}"; fi
[[ -n "$NOTES" ]] || NOTES="PY-Sys ${VERSION}"
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

# Catatan "Belum dirilis" menjadi bagian versi ini.
if [[ -n "${1:-}" ]]; then
    under_pending "- ${1}"
fi
under_pending "## ${VERSION} — $(date +%Y-%m-%d)\n"

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
