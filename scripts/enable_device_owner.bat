@echo off
echo =====================================================================
echo  ExamBroKu Android - Aktifkan Mode Device Owner (Full Kiosk 100%%)
echo =====================================================================
echo Syarat:
echo  1. USB Debugging aktif di HP/Tablet sekolah
echo  2. Tidak ada akun Google/email yang sedang login di perangkat
echo  3. Aplikasi ExamBroKu sudah terinstall
echo.
adb shell dpm set-device-owner id.sch.exambroku.exambroku_android/.ExamDeviceAdminReceiver
echo.
echo Jika muncul "Success", mode Kiosk Penuh (Device Owner) sudah aktif!
pause
