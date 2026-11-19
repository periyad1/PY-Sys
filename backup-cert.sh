#!/usr/bin/env bash
# Mencadangkan sertifikat "PY-Sys Local" (kunci + sertifikat) ke file .p12 berpassword.
# Simpan file ini di tempat aman (mis. flashdisk atau password manager), JANGAN di GitHub.
# Tanpa sertifikat ini, versi baru PY-Sys akan DITOLAK oleh pembaruan otomatis di Mac pengguna.
# Memulihkan di Mac baru: klik dua kali file .p12, masukkan password, lalu jalankan ./make-cert.sh
# (skrip itu akan mendeteksi sertifikat yang sudah ada).
set -euo pipefail
OUT="${1:-$HOME/Desktop/PY-Sys-Local-cadangan.p12}"
security find-identity -v -p codesigning 2>/dev/null | grep '"PY-Sys Local"' >/dev/null || { echo "✖ Sertifikat \"PY-Sys Local\" tidak ditemukan."; exit 1; }
read -r -s -p "Buat password untuk file cadangan: " PW; echo
read -r -s -p "Ulangi password: " PW2; echo
[[ "${PW}" == "${PW2}" && -n "${PW}" ]] || { echo "✖ Password tidak sama atau kosong."; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
# Ekspor semua identitas lalu ambil yang bernama PY-Sys Local (macOS akan meminta izin akses Keychain)
security export -k "$HOME/Library/Keychains/login.keychain-db" -t identities -f pkcs12 -P "${PW}" -o "${TMP}/all.p12"
cp "${TMP}/all.p12" "${OUT}"
echo "✔ Cadangan tersimpan: ${OUT}"
echo "  Catatan: file ini berisi semua identitas penandatangan di Keychain login Anda, termasuk PY-Sys Local."
