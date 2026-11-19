#!/bin/bash
# Membuat sertifikat penandatangan kode lokal "PY-Sys Local" (sekali saja).
# Dengan sertifikat tetap, macOS mengenali PY-Sys sebagai aplikasi yang sama setiap build,
# jadi izin Accessibility dan Automation tidak perlu diberikan ulang.
set -euo pipefail
NAME="PY-Sys Local"
KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep "\"$NAME\"" >/dev/null; then
    echo "✔ Sertifikat \"$NAME\" sudah ada. Tidak perlu dibuat lagi."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Sertifikat sudah diimpor dari cadangan (.p12) tetapi belum dipercaya: cukup tandai terpercaya,
# JANGAN buat baru (sertifikat baru = "cap" berbeda, pembaruan otomatis pengguna akan menolaknya).
if security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
    echo "▶ Sertifikat \"$NAME\" dari cadangan ditemukan. Menandainya terpercaya untuk code signing…"
    security find-certificate -c "$NAME" -p "$KC" > "$TMP/cert.pem"
    security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"
    security find-identity -v -p codesigning 2>/dev/null | grep "\"$NAME\"" >/dev/null && { echo "✔ Siap dipakai."; exit 0; }
    echo "✖ Masih belum terbaca. Buka Keychain Access → \"$NAME\" → Trust → Code Signing: Always Trust."
    exit 1
fi
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG

OPENSSL=/usr/bin/openssl
echo "▶ Membuat kunci dan sertifikat (berlaku 10 tahun)…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
LEGACY=""
"$OPENSSL" version | grep -q "^OpenSSL 3" && LEGACY="-legacy"
"$OPENSSL" pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout pass:pysys

echo "▶ Memasukkan ke Keychain login…"
security import "$TMP/id.p12" -k "$KC" -P pysys -T /usr/bin/codesign >/dev/null

echo "▶ Menandai sertifikat terpercaya untuk code signing (macOS akan meminta password Anda)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"

if security find-identity -v -p codesigning 2>/dev/null | grep "\"$NAME\"" >/dev/null; then
    echo "✔ Selesai. Jalankan ./build.sh --install, lalu beri izin Accessibility SEKALI lagi."
    echo "  Build berikutnya akan memakai sertifikat ini dan izinnya tetap tersimpan."
else
    echo "✖ Sertifikat belum terbaca sebagai identitas code signing. Buka Keychain Access,"
    echo "  cari \"$NAME\", klik dua kali → Trust → Code Signing: Always Trust."
    exit 1
fi
