# BersolekMart — GitHub Debug APK Build

Repository ini sengaja tidak menyimpan folder `android/`. GitHub Actions akan membuat platform Android secara otomatis menggunakan Flutter stable sebelum build.

## Cara pakai

1. Upload seluruh isi repository ini ke repository GitHub.
2. Commit/push ke branch `main` atau `master`, atau buka tab **Actions** lalu jalankan workflow **Build BersolekMart Debug APK** dengan **Run workflow**.
3. Tunggu job selesai.
4. Buka hasil workflow dan download artifact **`bersolekmart-debug-apk`**.
5. Extract artifact untuk mendapatkan:

```text
app-debug.apk
```

APK adalah **debug APK**, bukan release-signed APK.

## Backend lokal

XAMPP project:

```text
http://localhost/bersolekmart/
```

Android Emulator:

```text
http://10.0.2.2/bersolekmart/api/v1
```

HP Android fisik memakai IP LAN PC, misalnya:

```text
http://192.168.1.10/bersolekmart/api/v1
```

URL API juga bisa diubah dari halaman login aplikasi.

## Role

Satu APK memakai role dari backend:

- `konsumen` / `customer` → Customer UI
- `driver` → Driver UI
- `admin`, `operator`, `merchant` → ditolak oleh aplikasi mobile

## Catatan anti-mock location

Versi debug ini menggunakan `Position.isMocked` sebagai deteksi client-side awal dan tidak mengirim lokasi yang ditandai mock ke endpoint driver location. Ini belum merupakan boundary keamanan final; enforcement server-side, movement validation, geofence, dan Play Integrity dikerjakan pada fase berikutnya.
