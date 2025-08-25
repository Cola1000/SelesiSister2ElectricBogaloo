# Dokumentasi HTTP Web Server Assembly (asmhttpd)

Proyek ini adalah sebuah HTTP Web Server fungsional yang ditulis sepenuhnya dalam bahasa Assembly untuk arsitektur x86-64 di lingkungan Linux. Server ini dirancang untuk menjadi ringan, cepat, dan memenuhi semua persyaratan yang ditentukan.

## Arsitektur

Server ini dibuat untuk arsitektur **x86-64 (64-bit)** dan menggunakan system calls (syscalls) Linux secara langsung untuk operasi jaringan dan file. Proses kompilasi menggunakan `nasm` untuk merakit kode Assembly menjadi file objek.

---

## Fitur-Fitur yang Diimplementasikan

### 1. Mendengarkan pada Port Tertentu (Listening to Port)

Server dapat menerima argumen command-line `-p` untuk menentukan port TCP yang akan digunakan. Proses ini melibatkan tiga syscalls utama: `socket`, `bind`, dan `listen`.

**Cara Kerja:**
1.  **`socket()`**: Membuat endpoint komunikasi jaringan dan mengembalikan sebuah file descriptor.
2.  **`bind()`**: Menetapkan alamat (IP dan port) ke file descriptor socket yang telah dibuat.
3.  **`listen()`**: Menandai socket sebagai socket pasif yang akan digunakan untuk menerima koneksi masuk.

**Screenshot Kode (`server.asm`):**
!(https://i.imgur.com/gO0bN2t.png)

**Contoh Menjalankan:**
```bash
# Menjalankan server pada port 8080
./asmhttpd -p 8080 -d ./www
Server listening on [http://127.0.0.1:8080](http://127.0.0.1:8080) with docroot './www'...
````

### 2\. Forking Child Process untuk setiap Request

Untuk menangani beberapa koneksi secara bersamaan tanpa saling memblokir, server menggunakan model *pre-forking*. Setelah koneksi diterima oleh `accept()`, proses utama akan membuat proses anak (child) menggunakan syscall `fork()`.

**Cara Kerja:**

1.  Proses induk (parent) berada dalam *infinite loop* dan tugas utamanya hanya memanggil `accept()` untuk menunggu koneksi baru.
2.  Ketika koneksi baru masuk, `accept()` kembali dengan *file descriptor* untuk koneksi tersebut.
3.  Induk segera memanggil `fork()`.
4.  **Proses Anak**: `fork()` mengembalikan 0. Proses anak bertanggung jawab penuh untuk menangani request dari klien, setelah itu ia akan keluar (`exit()`).
5.  **Proses Induk**: `fork()` mengembalikan PID dari anak. Proses induk hanya menutup *file descriptor* koneksi di sisinya dan kembali ke `accept()` untuk menunggu koneksi berikutnya.

**Screenshot Kode (`server.asm`):**
\!(https://www.google.com/search?q=https://i.imgur.com/2U5Vn6g.png)

### 3\. Parsing HTTP Methods (GET, POST, PUT, DELETE)

Server dapat mem-parsing request line dari klien untuk mengidentifikasi metode HTTP yang digunakan.

**Cara Kerja:**

1.  Request dari klien dibaca ke dalam sebuah buffer.
2.  Kode akan mencari spasi pertama untuk memisahkan nama metode (misalnya, "GET") dari sisa request line.
3.  Nama metode kemudian dibandingkan dengan string yang telah ditentukan (`"GET"`, `"POST"`, dll.) untuk menentukan tindakan selanjutnya.

**Screenshot Kode (`server.asm`):**
\!(https://www.google.com/search?q=https://i.imgur.com/f0u9lWJ.png)

**Contoh Pengujian:**

```bash
# Uji metode GET
curl -v [http://127.0.0.1:8080/](http://127.0.0.1:8080/)

# Uji metode POST (server akan merespon 200 OK)
curl -v -X POST --data "test" [http://127.0.0.1:8080/anypath](http://127.0.0.1:8080/anypath)
```

### 4\. Melayani Permintaan File Statis

Server dapat menyajikan file dari direktori lokal yang ditentukan menggunakan argumen `-d`. Ini memungkinkan server untuk mengirimkan file HTML, CSS, JavaScript, gambar, dan lainnya.

**Cara Kerja:**

1.  Path yang diminta dari URL klien (misal: `/style.css`) digabungkan dengan path *document root* (misal: `./www`) untuk membentuk path file lokal (`./www/style.css`).
2.  Server menggunakan syscall `open()` untuk membuka file tersebut.
3.  Ukuran file didapatkan menggunakan `fstat()` untuk mengisi header `Content-Length`.
4.  Syscall `sendfile()` yang sangat efisien digunakan untuk menyalin data dari file descriptor file langsung ke file descriptor socket, menghindari penyalinan data yang tidak perlu ke *user space*.

**Screenshot Pengujian:**
\!(https://www.google.com/search?q=https://i.imgur.com/r6s2s1A.png)

### 5\. Melayani Permintaan Berdasarkan Rute/Path (Routing)

Server mengimplementasikan routing sederhana untuk menangani path tertentu secara khusus, bukan hanya sebagai file statis.

**Cara Kerja:**

  - Path yang telah di-parse akan dibandingkan dengan rute-rute yang telah didefinisikan secara internal.
  - `/hello`: Mengembalikan respons teks `Hello from Assembly!`.
  - `/auth`: Memerlukan Basic Authentication.
  - `/dyn/*`: Meneruskan permintaan ke plugin C eksternal.
  - Jika tidak ada rute yang cocok, server akan mencoba melayani permintaan sebagai file statis.

**Screenshot Kode (`server.asm`):**
\!(https://www.google.com/search?q=https://i.imgur.com/0F7eK1j.png)

-----

## Fitur Bonus

### 1\. Integrasi dengan Program Lain (Linking Binary C)

Server ini dapat memanggil fungsi yang ditulis dalam bahasa C. Rute yang diawali dengan `/dyn/` akan ditangani oleh file `plugin.c`.

**Cara Kerja:**

1.  `plugin.c` dikompilasi menjadi `plugin.o`.
2.  `Makefile` me-link `server.o` dengan `plugin.o` untuk membuat *binary* `asmhttpd`.
3.  Di dalam `server.asm`, fungsi C `plugin_dispatch` dideklarasikan sebagai `extern`.
4.  Ketika request untuk `/dyn/*` diterima, server memanggil fungsi C ini menggunakan *standard C calling convention* dan meneruskan detail request. Hasil dari fungsi C kemudian digunakan untuk membentuk respons HTTP.

**Contoh Pengujian:**

```bash
# Memanggil fungsi C untuk menjumlahkan dua angka
curl "[http://127.0.0.1:8080/dyn/add?a=100&b=23](http://127.0.0.1:8080/dyn/add?a=100&b=23)"
# Output: {"a":100,"b":23,"sum":123}
```

### 2\. [KREATIVITAS] Otentikasi & Logging Manual

  - **Basic Authentication:** Rute `/auth` dilindungi. Server mencari header `Authorization: Basic <token>` pada request. Ia akan membandingkan token base64 dengan nilai yang diharapkan (`YWRtaW46c2VjcmV0` untuk `admin:secret`). Jika gagal, server akan mengirim respons `401 Unauthorized`.
  - **Logging Manual:** Untuk membantu debugging dan memberikan feedback, server mencetak setiap request yang masuk ke `stdout`. Ini adalah bentuk logging manual yang sederhana namun efektif.

**Screenshot Logging:**
\!(https://www.google.com/search?q=https://i.imgur.com/x5Jk1vR.png)

### 3\. [EKSPERIMEN] Deployment

File untuk deployment sederhana telah disediakan di dalam direktori `deploy/`.

  - **`asm-httpd.service`**: Sebuah file unit `systemd` untuk menjalankan server sebagai layanan di latar belakang.
  - **`nginx.conf.example`**: Contoh konfigurasi NGINX untuk digunakan sebagai *reverse proxy* di depan server Assembly. Ini adalah praktik standar untuk deployment, memungkinkan NGINX menangani traffic HTTPS, kompresi, dan lainnya.

-----

## Petunjuk Penggunaan

1.  **Build Program:**
    Pastikan Anda memiliki `nasm` dan `gcc` terinstal. Kemudian jalankan `make`.

    ```bash
    make
    ```

2.  **Jalankan Server:**
    Gunakan binary yang telah dibuat, tentukan port dan direktori `www`.

    ```bash
    ./asmhttpd -p 8080 -d ./www
    ```

3.  **Akses Server:**
    Buka browser Anda dan akses `http://localhost:8080` atau gunakan `curl` untuk menguji berbagai endpoint yang tersedia.

### Update (v2)
- Fix route `/hello` checked **before** static path parsing so it always returns dynamic HTML.
- Make body parsing for **POST/PUT** robust against different newline styles (CRLF / LF).
