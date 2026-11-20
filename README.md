<p align="center"><img src="Support/logo.png" width="128" alt="Logo PY-Sys"></p>

<p align="center"><a href="https://github.com/periyad1/PY-Sys/actions/workflows/build.yml"><img src="https://github.com/periyad1/PY-Sys/actions/workflows/build.yml/badge.svg" alt="Build check"></a> <a href="https://github.com/periyad1/PY-Sys/releases"><img src="https://img.shields.io/github/downloads/periyad1/PY-Sys/total?label=unduhan%20%2F%20downloads&amp;color=orange" alt="Total unduhan"></a> <a href="https://github.com/periyad1/PY-Sys/releases/latest"><img src="https://img.shields.io/github/downloads/periyad1/PY-Sys/latest/total?label=versi%20terbaru%20%2F%20latest" alt="Unduhan versi terbaru"></a></p>

# PY-Sys — pemantau, pembersih & utilitas Mac di menu bar

PY-Sys adalah aplikasi menu bar untuk **semua Mac dengan RAM berapa pun** (8, 16, 24 GB atau lebih), Apple Silicon maupun Intel, macOS 13 Ventura atau lebih baru. Manfaatnya paling terasa di Mac 8 GB yang dipakai untuk banyak tab browser, beberapa monitor, dan agen AI, tetapi Mac dengan RAM besar juga terbantu untuk tetap rapi, terpantau, dan produktif.

Semua fitur memakai API publik macOS: tanpa root, tanpa mematikan SIP, dan tidak mengubah file sistem.

**[⬇︎ Unduh versi terbaru (DMG)](../../releases/latest)** · [English version ↓](#english)

**Syarat:** macOS 13 Ventura atau lebih baru, yaitu MacBook Pro 2017+, MacBook Air 2018+, MacBook 12″ 2017, iMac 2017+, Mac mini 2018+, serta semua Mac Apple Silicon (M1 dan sesudahnya).

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

PY-Sys is a menu bar app for **any Mac, whatever its RAM** (8, 16, 24 GB or more), on Apple Silicon or Intel with macOS 13 Ventura or later. It helps most on 8 GB Macs running many browser tabs, several displays and AI agents, and it keeps larger Macs tidy, monitored and productive too.

Every feature uses public macOS APIs: no root, no SIP changes, and no system files modified.

**[⬇︎ Download the latest version (DMG)](../../releases/latest)**

**Requirements:** macOS 13 Ventura or later, which means MacBook Pro 2017+, MacBook Air 2018+, MacBook 12″ 2017, iMac 2017+, Mac mini 2018+, and every Apple Silicon Mac (M1 and later).

### At a glance

- **Home**: a summary of RAM, swap, CPU and temperature; a feature search field; up to 10 favorite features; every feature in a grid by category.
- **Free up RAM** in one click: a before → after result, the apps that were frozen, the apps that were skipped with the reason, and a "Freeze more" button.
- **Welcome guide** in 4 steps on first launch: language, permissions (live ✓/✗ status), appearance, and tips. Reopen it from Settings → Show welcome guide.
- **Appearance**: 4 icon styles (Monochrome, By category, By feature, Outline), accent colors (PY-Sys orange, graphite, system blue and more, including a custom color), and Light/Dark/Pure dark modes, from the palette icon in the panel header.
- **Backup & problem reports**: export/import settings to another Mac, and a crash summary you can copy or report on GitHub (nothing is sent automatically).
- **Power button ⏻** in the panel footer: lock screen, sleep, log out, restart and shut down, with frozen apps safely thawed first.

### Features

#### Monitoring
| Feature | What it does |
| --- | --- |
| Dashboard | CPU, GPU, disk, RAM, fans and network on one screen |
| RAM | Memory pressure, composition (App/Wired/Compressed/Cache), swap, page-ins/outs, 10-minute charts |
| CPU & GPU | Per-core load (P/E on Apple Silicon), temperature, GPU, load average, top processes |
| Network & Sensors | Speed, interfaces, public IP; temperatures, fans, power, battery |
| AI Agents | Claude Code, Codex, Gemini, Ollama, MLX, Node/Python: RAM, CPU, pause/stop, runaway alerts |
| Browser | RAM per browser split into tabs, extensions and GPU; tab count |
| History | 24-hour/7-day charts, daily SSD writes, SSD life estimate, restart advice |

#### Cleaner
| Feature | What it does |
| --- | --- |
| Apps & Cryo-Sleep | RAM per app; freezes idle, hidden apps and thaws them when opened |
| Focus mode | Work profiles that freeze every app outside the profile in one click |
| Browser tabs | Save & close tabs, close duplicates, reopen any time |
| Storage | Caches, logs, developer caches, Trash, old downloads |
| Uninstaller | Removes apps along with their leftover files in ~/Library |
| Large & duplicate files | Finds large files and identical copies |

#### Utility
| Feature | What it does |
| --- | --- |
| Quick toggles | Quit all apps, keep awake, lock screen, Dark Mode, Dock and more |
| Right-Click+ | Extra Finder menu: new file, copy path, move to, folder colors |
| Windows | Snap windows with ⌃⌥, move between displays, save multi-display layouts |
| Clipboard | Copy history with ⌃⌥V |
| Displays | DDC brightness and a software dimmer for every display |
| Schedule | Automatic maintenance tasks at set times |
| Scroll Reverser | Separate scroll direction for trackpad and mouse |
| Tools | System info, battery health, PDF report export |

Also: two languages (English/Bahasa Indonesia), menu bar widgets (RAM, CPU, temperature, network, swap, AI agents), power saving while the panel is closed, and one-click automatic updates from GitHub Releases.

### Installing

1. Download **PY-Sys-x.y.z.dmg** from [Releases](../../releases/latest).
2. Open the DMG, drag **PY-Sys** to **Applications**, then open it.
3. (Optional) Verify the download: `shasum -a 256 ~/Downloads/PY-Sys-x.y.z.dmg` must match the SHA-256 code on the release page.
4. If macOS warns about an "unidentified developer": **System Settings → Privacy & Security → Open Anyway**.
5. The welcome guide appears and walks you through the permissions. Accessibility is needed for Windows, Clipboard, Right-Click+ and Scroll Reverser.
6. Automatic updates are on from the start (official repo `periyad1/PY-Sys`). PY-Sys notifies you when a new version is out and only installs releases signed by the official author.

### Building from source

Requires the Command Line Tools (`xcode-select --install`); full Xcode is not needed.

```bash
./make-cert.sh        # once: a local certificate so macOS permissions survive every build
./build.sh --install  # universal build (arm64 + x86_64), installed in /Applications
./build.sh --dmg      # creates build/PY-Sys-<version>.dmg
./build.sh --all      # both
```

#### Releasing

Small fixes are collected first and released together, so users don't get update notifications too often. All notes live in [CATATAN-RILIS.md](CATATAN-RILIS.md) (release notes, in Indonesian).

```bash
./release.sh --simpan "Fix text X"   # commit & push code only; the note goes under "Belum dirilis" (unreleased)
./release.sh                         # release: build DMG, push, GitHub Release with every unreleased note
```

Every push is built automatically by GitHub Actions (the **Build check** badge at the top).

---

© 2026 Periyadi · periyadi@telkomuniversity.ac.id
