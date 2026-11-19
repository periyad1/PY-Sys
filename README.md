# PY-Sys — pemantau & pengatur memori di menu bar untuk MacBook M2 8 GB

PY-Sys (sebelumnya PY-Sys). Semua yang ada di sini memakai API publik macOS,
tanpa root, tanpa mematikan SIP, dan tidak mengubah file sistem.

## Fitur
| Fitur | Cara kerja |
|---|---|
| **Monitor memori** | Memory pressure kernel, App/Wired/Terkompresi/Cache, rasio kompresi, swap terpakai, laju swap-out (grafik 10 menit). Ikon menu bar berubah: chip → ⚠ → 🔥. |
| **Pantauan SSD** | Byte yang ditulis ke `disk0` sejak boot dan laju tulisnya. Ini tanda langsung seberapa keras swap menggerus SSD. Opsional: total tulis seumur hidup + % keausan via `smartctl`. |
| **Cryo-Sleep** | App dibekukan (`SIGSTOP`) hanya jika: bukan app aktif, **tidak punya jendela terlihat di monitor mana pun**, idle ≥ N menit, CPU < 1%, dan tidak ada di whitelist. App dicairkan otomatis (`SIGCONT`) saat diklik di Dock atau Cmd-Tab, atau saat jendelanya muncul lagi. |
| **Pemakai terbesar** | Proses dikelompokkan per aplikasi (helper Chrome/Electron digabung). Tombol bekukan / cairkan / tutup per aplikasi. |
| **Peringatan** | Notifikasi kalau satu app melewati batas (default 2,5 GB) atau tekanan memori kritis. |

### Pengaman
- Semua app beku dicairkan saat PY-Sys keluar, menerima SIGTERM/SIGINT, logout, atau shutdown.
- Daftar app beku disimpan ke `~/Library/Application Support/PY-Sys/frozen.json`. Kalau PY-Sys crash, semuanya dicairkan saat PY-Sys dibuka lagi.
- Finder/Dock tidak pernah bisa dibekukan.
- Whitelist bawaan berisi terminal & IDE (tempat agen AI jalan), Docker, Ollama, LM Studio, Claude/ChatGPT desktop, aplikasi chat, Zoom/Teams, musik, dan DisplayLink.

## Build (di MacBook)
Butuh macOS 13+ dan Xcode Command Line Tools.
```bash
xcode-select --install          # sekali saja, kalau belum
cd PY-Sys
chmod +x build.sh
./build.sh --install            # build, salin ke /Applications, jalankan
```
Bisa juga buka `Package.swift` di Xcode lalu Run.

Opsional, untuk data keausan SSD seumur hidup:
```bash
brew install smartmontools
```
Setelah itu aktifkan **Atur → Jalankan saat login**.

## Batasan yang perlu diketahui
- **Tidak menambah RAM.** Cryo-Sleep hanya membuat macOS lebih leluasa mengompres atau swap app yang memang tidak dipakai.
- **Safari:** tab-tabnya berjalan sebagai proses XPC terpisah (`com.apple.WebKit.WebContent`), jadi membekukan Safari tidak ikut membekukan tab-tabnya. Chrome, Edge, Brave, dan Arc ikut beku seluruhnya.
- App yang dibekukan tidak menerima notifikasi atau pesan. Masukkan ke whitelist kalau perlu.
- Kalau app beku tidak bangun saat diklik di Dock, buka menu PY-Sys → **Cairkan**.
- App ini belum di-notarize (hanya ad-hoc sign). Kalau Gatekeeper menolak: klik kanan → Open.

## Tips untuk setup 8 GB + 2 monitor
- Chrome: Settings → Performance → **Memory Saver: Maximum**.
- Monitor kedua via DisplayLink? Driver-nya ikut makan RAM/CPU. Cek pemakaiannya di tab **Aplikasi**.
- Pakai agen AI lewat API cloud, bukan model lokal. Model 7B saja butuh ±4–5 GB.
- Pantau **Laju swap-out**. Kalau sering di atas 0 saat kerja normal, Mac ini memang sudah kekurangan RAM untuk beban itu.
