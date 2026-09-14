Taruh file `yolov8n-pose.pt` kamu di folder ini (models/).

File model tidak disertakan ulang di paket ini karena ukurannya besar (~6.8MB)
dan kamu sudah punya file aslinya -- tinggal pindahkan dari lokasi lama ke
sini. app/pi_publisher_yolo.py dan tools/pose_detector.py sudah dikonfigurasi
untuk otomatis mencari model di folder models/ ini (relatif terhadap lokasi
script masing-masing), jadi begitu file model ada di sini, tidak perlu
ubah apapun lagi.

Kalau kamu masih menyimpan yolov8n.pt (versi non-pose, bukan yolov8n-pose.pt)
dari eksperimen awal -- itu sudah TIDAK dipakai kode manapun lagi, aman
dihapus atau diabaikan.
