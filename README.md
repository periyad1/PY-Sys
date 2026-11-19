<p align="center"><img src="Support/logo.png" width="128" alt="Logo PY-Sys"></p>

<p align="center"><a href="https://github.com/periyad1/PY-Sys/actions/workflows/build.yml"><img src="https://github.com/periyad1/PY-Sys/actions/workflows/build.yml/badge.svg" alt="Build check"></a></p>

# PY-Sys — pemantau, pembersih & utilitas Mac di menu bar

PY-Sys adalah aplikasi menu bar untuk **semua Mac dengan RAM berapa pun** (8, 16, 24 GB atau lebih), Apple Silicon maupun Intel, macOS 13 Ventura atau lebih baru. Manfaatnya paling terasa di Mac 8 GB yang dipakai untuk banyak tab browser, beberapa monitor, dan agen AI, tetapi Mac dengan RAM besar juga terbantu untuk tetap rapi, terpantau, dan produktif.

Semua fitur memakai API publik macOS: tanpa root, tanpa mematikan SIP, dan tidak mengubah file sistem.

**[⬇︎ Unduh versi terbaru (DMG)](../../releases/latest)**

## Sekilas

- **Beranda**: ringkasan RAM, swap, CPU, dan suhu; kolom cari fitur; hingga 10 fitur favorit; semua fitur dalam grid per kategori.
- **Bebaskan RAM** satu klik: hasil sebelum → sesudah, daftar app yang dibekukan, app yang dilewati beserta alasannya, dan tombol "Bekukan lebih banyak".
- **Panduan awal** 4 langkah saat pertama dibuka: bahasa, izin (status ✓/✗ langsung), tampilan, dan tips. Bisa dibuka lagi di Pengaturan → Tampilkan panduan awal.
- **Tampilan**: 4 gaya ikon (Monokrom, Per kategori, Per fitur, Garis), warna aksen (oranye PY-Sys, grafit, biru sistem, dan lainnya, termasuk warna bebas), mode Terang/Gelap/Gelap pekat, lewat ikon palet di kepala panel.
- **Cadangan & laporan masalah**: ekspor/impor pengaturan ke Mac lain, dan ringkasan crash yang bisa disalin atau dilaporkan di GitHub (tidak ada yang dikirim otomatis).
- **Tombol daya ⏻** di kaki panel: kunci layar, tidur, keluar, restart, dan matikan, dengan app beku dicairkan dulu dengan aman.

## Fitur

### Monitoring
| Fitur | Isi |
| --- | --- |
| Dashboard | CPU, GPU, disk, RAM, kipas, dan internet dalam satu layar |
| RAM | Tekanan memori, komposisi (App/Wired/Terkompresi/Cache), swap, page-in/out, grafik 10 menit |
| CPU & GPU | Beban per inti (P/E di Apple Silicon), suhu, GPU, load average, proses teratas |
| Jaringan & Sensor | Kecepatan, antarmuka, IP publik; suhu, kipas, daya, baterai |
| Agen AI | Claude Code, Codex, Gemini, Ollama, MLX, Node/Python: RAM, CPU, jeda/hentikan, peringatan macet |
| Browser | RAM per browser dirinci tab, ekstensi, GPU; jumlah tab |
| Riwayat | Grafik 24 jam/7 hari, tulis SSD per hari, perkiraan umur SSD, saran restart |

### Cleaner
| Fitur | Isi |
| --- | --- |
| Aplikasi & Cryo-Sleep | RAM per aplikasi; membekukan app idle yang tidak terlihat dan mencairkannya saat dibuka |
| Mode fokus | Profil kerja yang membekukan app di luar profil dengan satu klik |
| Tab browser | Simpan & tutup tab, tutup duplikat, buka lagi kapan saja |
| Penyimpanan | Cache, log, cache developer, Sampah, unduhan lama |
| Uninstaller | Hapus aplikasi beserta file sisanya di ~/Library |
| File besar & duplikat | Temukan file besar dan salinan identik |

### Utility
| Fitur | Isi |
| --- | --- |
| Toggle cepat | Tutup semua app, tetap terjaga, kunci layar, Dark Mode, Dock, dan lainnya |
| Klik Kanan+ | Menu Finder tambahan: file baru, salin path, pindah ke, warna folder |
| Jendela | Snap jendela dengan ⌃⌥, pindah monitor, simpan tata letak multi-monitor |
| Clipboard | Riwayat salin dengan ⌃⌥V |
| Monitor | Kecerahan DDC dan peredup software untuk semua layar |
| Jadwal | Tugas perawatan otomatis pada jam tertentu |
| Scroll Reverser | Arah scroll terpisah untuk trackpad dan mouse |
| Alat | Info sistem, kesehatan baterai, ekspor laporan PDF |

Juga: dua bahasa (Indonesia/English), widget menu bar (RAM, CPU, suhu, jaringan, swap, agen AI), mode hemat daya saat panel tertutup, dan pembaruan otomatis satu klik dari GitHub Releases.

## Memasang

1. Unduh **PY-Sys-x.y.z.dmg** dari [Releases](../../releases/latest).
2. Buka DMG, seret **PY-Sys** ke **Applications**, lalu buka.
3. (Opsional) Cek keaslian: `shasum -a 256 ~/Downloads/PY-Sys-x.y.z.dmg` harus sama dengan kode SHA-256 di halaman rilis.
4. Bila muncul peringatan "pengembang tidak dikenal": **System Settings → Privacy & Security → Open Anyway**.
5. Panduan awal muncul dan menuntun pemberian izin. Accessibility dibutuhkan untuk Jendela, Clipboard, Klik Kanan+, dan Scroll Reverser.
6. Pembaruan otomatis sudah aktif sejak awal (repo resmi `periyad1/PY-Sys`). PY-Sys memberi notifikasi saat ada versi baru dan hanya memasang rilis yang ditandatangani pembuat resmi.

## Build dari kode

Butuh Command Line Tools (`xcode-select --install`), tidak perlu Xcode lengkap.

```bash
./make-cert.sh        # sekali saja: sertifikat lokal agar izin macOS tidak hilang tiap build
./build.sh --install  # build universal (arm64 + x86_64) dan pasang di /Applications
./build.sh --dmg      # buat build/PY-Sys-<versi>.dmg
./build.sh --all      # keduanya
```

### Merilis

Perbaikan kecil dikumpulkan dulu, lalu dirilis bersama, supaya pengguna tidak terlalu sering mendapat notifikasi pembaruan. Semua catatan ada di [CATATAN-RILIS.md](CATATAN-RILIS.md).

```bash
./release.sh --simpan "Perbaiki teks X"   # commit & push kode saja, catatan masuk "Belum dirilis"
./release.sh                              # rilis: build DMG, push, GitHub Release berisi semua catatan "Belum dirilis"
```

Setiap push otomatis di-build oleh GitHub Actions (lencana **Build check** di atas).

---

## English

PY-Sys is a menu bar app that monitors, cleans and looks after **any Mac, whatever its RAM** (8, 16, 24 GB or more), on Apple Silicon or Intel with macOS 13 Ventura or later. It helps most on 8 GB Macs running many browser tabs, several displays and AI agents, and keeps larger Macs tidy and well monitored too. It uses only public macOS APIs: no root, no SIP changes, no system files modified.

Highlights: a Home grid with favorites and search, one-click Free RAM with a before/after report, a 4-step welcome guide for permissions and appearance, four icon styles with accent colors and dark modes, a power menu (lock, sleep, log out, restart, shut down), settings export/import, and simple crash reports you can send on GitHub.

Download the latest DMG from [Releases](../../releases/latest), drag PY-Sys to Applications, and allow it under Privacy & Security if macOS warns about an unidentified developer. The welcome guide walks you through the permissions.

© 2026 Periyadi · periyadi@telkomuniversity.ac.id
