#!/usr/bin/env bash
# Mengamankan repo GitHub PY-Sys:
#   1. memeriksa Collaborator (hanya Anda yang boleh menulis)
#   2. memeriksa verifikasi dua langkah (2FA) akun GitHub
#   3. melindungi branch main (tidak bisa dihapus / di-force-push; orang lain wajib lewat Pull Request)
#   4. menyamakan email commit dengan akun GitHub (nama Anda tidak muncul dua kali)
set -uo pipefail
cd "$(dirname "$0")"

command -v gh >/dev/null || { echo "✖ GitHub CLI belum terpasang: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✖ Belum login GitHub: gh auth login"; exit 1; }

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
OWNER="${REPO%%/*}"
echo "Repo: ${REPO}"
echo

echo "1) Collaborator"
OTHERS="$(gh api "repos/${REPO}/collaborators" --jq '.[].login' 2>/dev/null | grep -vx "${OWNER}" || true)"
if [[ -z "${OTHERS}" ]]; then
    echo "   ✔ Tidak ada Collaborator lain. Orang lain hanya bisa mengusulkan perubahan lewat Pull Request."
else
    for u in ${OTHERS}; do
        read -r -p "   ⚠ ${u} punya akses menulis. Hapus aksesnya? [y/N] " a
        if [[ "${a}" == "y" || "${a}" == "Y" ]]; then
            gh api -X DELETE "repos/${REPO}/collaborators/${u}" >/dev/null && echo "   ✔ ${u} dihapus."
        fi
    done
fi
echo

echo "2) Verifikasi dua langkah (2FA)"
TFA="$(gh api user --jq '.two_factor_authentication' 2>/dev/null || echo unknown)"
if [[ "${TFA}" == "true" ]]; then
    echo "   ✔ 2FA aktif."
else
    echo "   ⚠ 2FA belum aktif (atau tidak terbaca). Membuka halaman pengaturan keamanan…"
    echo "     Klik 'Enable two-factor authentication', lalu ikuti langkahnya (aplikasi authenticator atau passkey)."
    open "https://github.com/settings/security" 2>/dev/null || true
fi
echo

echo "3) Perlindungan branch main"
if gh api -X PUT "repos/${REPO}/branches/main/protection" --input - >/dev/null 2>&1 <<'JSON'
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
then
    echo "   ✔ main dilindungi: tidak bisa dihapus atau ditimpa paksa; perubahan dari orang lain wajib lewat Pull Request."
    echo "     Anda (pemilik) tetap bisa push langsung, jadi ./release.sh tetap berjalan."
else
    echo "   ⚠ Gagal mengatur perlindungan branch. Atur manual: GitHub → repo → Settings → Branches → Add rule (main)."
fi
echo

echo "4) Email commit"
ID="$(gh api user --jq .id)"
LOGIN="$(gh api user --jq .login)"
NOREPLY="${ID}+${LOGIN}@users.noreply.github.com"
CUR="$(git config user.email || true)"
if [[ "${CUR}" == "${NOREPLY}" ]]; then
    echo "   ✔ Email commit sudah sesuai akun GitHub."
else
    git config user.email "${NOREPLY}"
    git config user.name "${LOGIN}"
    echo "   ✔ Email commit untuk repo ini diganti ke ${NOREPLY} (email asli Anda tidak tampil di GitHub)."
fi
echo

echo "Selesai. Jangan lupa cadangkan sertifikat penandatangan sekali: ./backup-cert.sh"
