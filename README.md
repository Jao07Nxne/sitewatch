# SiteWatch - ระบบเฝ้าระวังเว็บไซต์และบริการอัตโนมัติ

**SiteWatch** คือเครื่องมืออัตโนมัติสำหรับผู้ดูแลระบบ พัฒนาด้วย Shell Script ตามมาตรฐาน POSIX/Bash เพื่อตรวจสอบความพร้อมใช้งานและประสิทธิภาพของบริการเครือข่าย ทั้ง Web Services (HTTP/HTTPS), Domain Name Resolution (DNS) และ TCP Ports พร้อมระบบแจ้งเตือนเมื่อสถานะเปลี่ยนแปลง และคำนวณสถิติ Uptime รายงานผลอัตโนมัติผ่าน Systemd Timer

---

## 👥 สมาชิกกลุ่ม

* **66050027** นายกันตวัฒน์ แช่มช้อย
* **66050160** นายเตชสิทธิ์ วาณิชภัทรกุล
* **66050193** นายธัชชัย ลิ่มพิทักษ์

---

## 📁 โครงสร้างโปรเจกต์

ตามข้อกำหนดโครงสร้าง Git Repository ของรายวิชา:

```text
sitewatch/
├── README.md                      # เอกสารอธิบายการติดตั้งและใช้งาน
├── install.sh                     # สคริปต์ติดตั้งระบบและเปิดใช้งาน systemd timer
├── uninstall.sh                   # สคริปต์ถอนการติดตั้งและลบไฟล์ทั้งหมด
├── bin/
│   ├── sitewatch.sh               # สคริปต์หลัก 
│   ├── prober.sh                  # โมดูลตรวจสอบเครือข่าย 
│   ├── metric.sh                  # โมดูลบันทึก CSV และคำนวณ Uptime % ด้วย awk
│   └── state_alert.sh             # โมดูลตรวจสอบ State Change และจัดการแจ้งเตือน
├── config/
│   └── sitewatch.conf             # ไฟล์กำหนดค่าเป้าหมายและระบบ
└── systemd/
    ├── sitewatch.service          # Systemd Service Unit (Type=oneshot)
    └── sitewatch.timer            # Systemd Timer Unit (ตั้งเวลาทำงานทุก 2 นาที)
```

---

## ⚙️ ข้อกำหนดระบบ

* **ระบบปฏิบัติการ:** Ubuntu Server 22.04 / 24.04 LTS หรือ Rocky Linux 9
* **แพ็กเกจที่จำเป็น:** `bash`, `curl`, `netcat` (`nc`), `awk`, `grep`, `systemd`

### ติดตั้งเครื่องมือที่จำเป็น
> **หมายเหตุ:** สคริปต์ `install.sh` จะทำการตรวจสอบและติดตั้งแพ็กเกจที่จำเป็นผ่าน Package Manager (`apt` สำหรับ Ubuntu/Debian หรือ `dnf`/`yum` สำหรับ Rocky Linux) ให้โดยอัตโนมัติขณะรันติดตั้ง หรือสามารถติดตั้งด้วยตนเองล่วงหน้าได้ดังนี้:

```bash
sudo apt update && sudo apt install -y curl netcat-openbsd gawk dnsutils
```

---

## 🚀 วิธีการติดตั้ง

1. **Clone Repository:**
   ```bash
   git clone https://github.com/Jao07Nxne/sitewatch.git
   cd sitewatch
   ```

2. **ดำเนินการติดตั้งด้วยสิทธิ์ Root:**
   ```bash
   sudo ./install.sh
   ```
   > **หมายเหตุ:** สคริปต์จะคัดลอกไฟล์โปรแกรมไปยัง `/opt/sitewatch/bin/`, ติดตั้งไฟล์คอนฟิกที่ `/etc/sitewatch/sitewatch.conf`, สร้างคำสั่งลัด `/usr/local/bin/sitewatch` และเปิดใช้งาน Systemd Timer อัตโนมัติ

3. **ตรวจสอบสถานะการทำงานของตัวตั้งเวลา:**
   ```bash
   systemctl list-timers sitewatch.timer
   ```

---

## 📖 วิธีการใช้งาน

สามารถเรียกใช้งานคำสั่ง `sitewatch` ผ่าน Terminal ได้โดยตรง:

```bash
sitewatch [-c config] [-v] [-n] [-h]
```

### คำอธิบาย Options:
| Flag | รายละเอียด |
| :--- | :--- |
| `-h` | แสดงคู่มือช่วยเหลือและวิธีใช้งาน |
| `-c FILE` | กำหนดพาธไฟล์ config ที่ต้องการใช้งาน (ค่าเริ่มต้น: `/etc/sitewatch/sitewatch.conf`) |
| `-v` | เปิดโหมด Verbose เพื่อแสดงขั้นตอนการทำงานและรายละเอียดการ Probe อย่างละเอียด |
| `-n` | โหมด Dry-run จำลองการทำงานโดยไม่มีการบันทึกทับไฟล์ CSV หรือ State File จริง |

### ตัวอย่างคำสั่ง:

* ตรวจสอบและแสดงผลแบบละเอียด:
  ```bash
  sitewatch -v
  ```

* จำลองการทำงานโดยไม่แตะต้องระบบจริง:
  ```bash
  sitewatch -v -n
  ```

* เรียกดูรายงานสถิติ Uptime ล่าสุดจาก Log ของเซอร์วิสเบื้องหลัง:
  ```bash
  journalctl -u sitewatch.service -n 30 --no-pager
  ```

---

## 📝 ตัวอย่างไฟล์คอนฟิก (`/etc/sitewatch/sitewatch.conf`)

ผู้ดูแลระบบสามารถปรับแต่งเป้าหมายการเฝ้าระวังได้โดยแก้ไขไฟล์ `/etc/sitewatch/sitewatch.conf`:

```bash
# ช่วงเวลา Timeout ในการตรวจสอบแต่ละเป้าหมาย (วินาที)
PROBE_TIMEOUT=3

# รายการเป้าหมาย HTTP/HTTPS (ตรวจสอบ Status Code และ Latency ด้วย curl)
HTTP_TARGETS=(
    "http://127.0.0.1:8080"
    "https://www.google.com"
)

# รายการโดเมนที่ต้องการตรวจ DNS Resolution (ด้วย getent หรือ dig)
DNS_TARGETS=(
    "google.com"
)

# รายการเซอร์วิส TCP host:port (ตรวจสอบการเปิดของพอร์ตด้วย nc)
PORT_TARGETS=(
    "127.0.0.1:8080"
    "1.1.1.1:53"
)

# พาธสำหรับจัดเก็บไฟล์ข้อมูลระบบ
CSV_LOG_FILE="/var/log/sitewatch/metrics.csv"
STATE_FILE="/var/lib/sitewatch/state.env"
```

---

## 🗑️ วิธีการถอนการติดตั้ง

หากต้องการนำระบบออกจากเครื่องเซิร์ฟเวอร์:

```bash
sudo ./uninstall.sh
```