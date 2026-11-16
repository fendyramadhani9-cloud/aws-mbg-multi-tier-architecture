# Panduan Membangun Infrastruktur Multi-Tier High Availability di AWS

Panduan langkah demi langkah untuk membangun arsitektur aplikasi web multi-tier (*Front End*, *Back End*, *Database*, *Shared Session*, *Object Storage*, dan *Notification*) dengan keamanan jaringan privat dan skalabilitas otomatis di AWS Region **`us-east-1`**.

---

## Daftar Script Cepat

| Komponen | File Script | Raw URL (Download / `curl`) |
| :--- | :--- | :--- |
| **EC2 Back End** | [`scripts/backend.sh`](scripts/backend.sh) | [Raw `backend.sh`](https://raw.githubusercontent.com/fendyramadhani9-cloud/aws-mbg-multi-tier-architecture/main/scripts/backend.sh) |
| **EC2 Front End (Pre-Prod)** | [`scripts/frontend.sh`](scripts/frontend.sh) | [Raw `frontend.sh`](https://raw.githubusercontent.com/fendyramadhani9-cloud/aws-mbg-multi-tier-architecture/main/scripts/frontend.sh) |
| **Launch Template User Data** | [`scripts/launch-template-userdata.sh`](scripts/launch-template-userdata.sh) | [Raw `launch-template-userdata.sh`](https://raw.githubusercontent.com/fendyramadhani9-cloud/aws-mbg-multi-tier-architecture/main/scripts/launch-template-userdata.sh) |

---

## Persiapan Awal & Contoh Format Resource yang Dicatat
- Pastikan seluruh resource dibuat di Region **`us-east-1` (N. Virginia)**.
- Selama proses pembuatan, catat nilai-nilai berikut (contoh format asli agar mudah dikenali):
  - **AWS Account ID**: contoh `937385515130`
  - **RDS Endpoint**: contoh `mbg-rds-mysql.c1fa8qkqs4ma.us-east-1.rds.amazonaws.com`
  - **S3 Bucket Name**: contoh `mbg-uploads-937385515130-us-east-1-an`
  - **SNS Topic ARN**: contoh `arn:aws:sns:us-east-1:937385515130:mbg-sns-notifikasi`
  - **EFS File System ID**: contoh `fs-03504232a17c81d42`
  - **Private IP EC2 Back End**: contoh `10.20.10.134`

---

## Langkah 1: Membuat VPC & 7 Subnet

1. Buat VPC baru:
   - **Name**: `mbg-vpc`
   - **IPv4 CIDR**: `10.20.0.0/16`

2. Buat **7 Subnet** di dalam `mbg-vpc`:

| Nama Subnet | CIDR Block | Availability Zone | Auto-assign Public IPv4 |
| :--- | :--- | :--- | :---: |
| `mbg-subnet-public-alb-1a` | `10.20.1.0/24` | `us-east-1a` | **Enable (Ya)** |
| `mbg-subnet-public-alb-1b` | `10.20.2.0/24` | `us-east-1b` | **Enable (Ya)** |
| `mbg-subnet-private-fe-1a` | `10.20.11.0/24` | `us-east-1a` | Disable |
| `mbg-subnet-private-fe-1b` | `10.20.12.0/24` | `us-east-1b` | Disable |
| `mbg-subnet-private-be` | `10.20.10.0/24` | `us-east-1a` | Disable |
| `mbg-subnet-db-1a` | `10.20.20.0/24` | `us-east-1a` | Disable |
| `mbg-subnet-db-1b` | `10.20.21.0/24` | `us-east-1b` | Disable |

> **Catatan:** Pada 2 subnet Public ALB (`mbg-subnet-public-alb-1a` & `1b`), buka **Actions → Edit subnet settings** lalu centang **Enable auto-assign public IPv4 address**.

---

## Langkah 2: Internet Gateway, NAT Gateway & Route Table

1. **Internet Gateway**:
   - Buat IGW bernama `mbg-igw`.
   - Klik **Actions → Attach to VPC** → pilih `mbg-vpc`.

2. **NAT Gateway**:
   - Name / Tag `Name`: `mbg-natgw-1a` *(pastikan tag Name terisi)*
   - Subnet: `mbg-subnet-public-alb-1a`
   - Connectivity type: **Public**
   - Elastic IP: Klik **Allocate Elastic IP**.

3. **Route Table Public (`mbg-rt-public`)**:
   - Tambah route: `0.0.0.0/0` → Target: Internet Gateway (`mbg-igw`).
   - **Subnet associations**: `mbg-subnet-public-alb-1a` dan `mbg-subnet-public-alb-1b`.

4. **Route Table Private (`mbg-rt-private`)**:
   - Tambah route: `0.0.0.0/0` → Target: NAT Gateway (`mbg-natgw-1a`).
   - **Subnet associations**: `mbg-subnet-private-fe-1a`, `mbg-subnet-private-fe-1b`, dan `mbg-subnet-private-be`.
   - *(Subnet DB dibiarkan terisolasi tanpa route ke internet)*.

---

## Langkah 3: Security Groups (5 SG)

Buat 5 Security Group di dalam `mbg-vpc` dengan aturan **Inbound Rules** berikut:

| Nama Security Group | Protocol & Port | Source |
| :--- | :--- | :--- |
| `mbg-sg-alb` | HTTP (`TCP 80`) | `0.0.0.0/0` |
| `mbg-sg-fe` | SSH (`TCP 22`), HTTP (`TCP 80`) | `0.0.0.0/0` |
| `mbg-sg-be` | SSH (`TCP 22`), HTTP (`TCP 80`) | `0.0.0.0/0` |
| `mbg-sg-rds` | MYSQL/Aurora (`TCP 3306`) | `0.0.0.0/0` |
| `mbg-sg-efs` | NFS (`TCP 2049`) | `mbg-sg-fe` (atau `0.0.0.0/0`) |

---

## Langkah 4: Database RDS MySQL

1. Buat **DB Subnet Group**:
   - Name: `mbg-db-subnet-group`
   - VPC: `mbg-vpc`
   - Availability Zones: `us-east-1a`, `us-east-1b`
   - Subnets: `mbg-subnet-db-1a` dan `mbg-subnet-db-1b`

2. Buat **RDS MySQL**:
   - Engine: **MySQL** (Template: **Free tier**)
   - DB instance identifier: `mbg-rds-mysql`
   - Master username: `admin`
   - Master password: `12345678`
   - Instance class: `db.t3.micro` (Single-AZ)
   - DB subnet group: `mbg-db-subnet-group`
   - Public access: **No**
   - VPC security group: `mbg-sg-rds`
   - **Additional configuration → Initial database name**: `mbg_db`

3. Tunggu sampai status **Available**, lalu catat **Endpoint RDS** (contoh: `mbg-rds-mysql.c1fa8qkqs4ma.us-east-1.rds.amazonaws.com`, port `3306`).

---

## Langkah 5: S3 Bucket & SNS Topic

1. **S3 Bucket**:
   - Bucket name (Account Regional): `mbg-uploads-<ACCOUNT_ID>-us-east-1-an` *(contoh: `mbg-uploads-937385515130-us-east-1-an`)*
   - Region: `us-east-1`
   - **Block all public access**: Centang semua (Aktif).
   - Buat 2 folder/prefix di dalam bucket: `aduan/` dan `laporan/`.

2. **SNS Topic & Subscription**:
   - Buat Topic bertipe **Standard** dengan nama `mbg-sns-notifikasi`.
   - Buat Subscription: Protocol **Email**, Endpoint: `ukkce2627@smkn1bms.sch.id`.
   - Pastikan status subscription sudah **Confirmed**.
   - Catat **Topic ARN** (contoh: `arn:aws:sns:us-east-1:937385515130:mbg-sns-notifikasi`).

---

## Langkah 6: EFS Shared Session

1. Buat File System di EFS:
   - Name: `mbg-efs-fe-session`
   - VPC: `mbg-vpc`
   - Mode: **Regional**, Performance: **General Purpose**, Throughput: **Bursting**
2. Di tab **File system lifecycle management**: atur **Transition into Archive** menjadi **None**.
3. Di tab **Network → Manage**: pastikan Mount Target aktif di `mbg-subnet-private-fe-1a` dan `mbg-subnet-private-fe-1b` menggunakan Security Group `mbg-sg-efs`.
4. Catat **File System ID** (contoh: `fs-03504232a17c81d42`).

---

## Langkah 7: EC2 Back End (`mbg-ec2-be`)

1. Launch EC2 Instance:
   - Name: `mbg-ec2-be`
   - AMI: **Amazon Linux 2023** | Instance type: `t3.micro`
   - VPC: `mbg-vpc` | Subnet: `mbg-subnet-private-be`
   - Auto-assign public IP: **Disable**
   - Security Group: `mbg-sg-be`
   - **Advanced details → IAM instance profile**: `LabInstanceProfile`

2. Buka script setup Back End: 👉 **[`scripts/backend.sh`](scripts/backend.sh)**
   - Copy isinya ke **User Data** (atau jalankan via SSM Session Manager).
   - Ganti 3 variabel di bagian paling atas script dengan milikmu:
     - `RDS_HOST` → contoh: `"mbg-rds-mysql.c1fa8qkqs4ma.us-east-1.rds.amazonaws.com"`
     - `S3_BUCKET` → contoh: `"mbg-uploads-937385515130-us-east-1-an"`
     - `SNS_TOPIC_ARN` → contoh: `"arn:aws:sns:us-east-1:937385515130:mbg-sns-notifikasi"`

3. Catat **Private IP** dari `mbg-ec2-be` setelah instance berjalan (contoh: `10.20.10.134`).

---

## Langkah 8: EC2 Front End Sementara & Pembuatan AMI (`mbg-ami-fe`)

1. Launch EC2 sementara (`mbg-ec2-fe-temp`):
   - AMI: **Amazon Linux 2023** | Instance type: `t3.micro`
   - Subnet: `mbg-subnet-private-fe-1a` | Auto-assign public IP: **Disable**
   - Security Group: `mbg-sg-fe` | IAM instance profile: `LabInstanceProfile`

2. Buka script setup Front End: 👉 **[`scripts/frontend.sh`](scripts/frontend.sh)**
   - Copy isinya ke **User Data** (atau jalankan via SSM Session Manager).
   - Ganti 2 variabel di bagian paling atas script dengan milikmu:
     - `EFS_ID` → contoh: `"fs-03504232a17c81d42"`
     - `BE_PRIVATE_IP` → contoh: `"10.20.10.134"`

3. Setelah `/health.php` merespons OK dan EFS ter-mount, buat **AMI** dari `mbg-ec2-fe-temp` bernama **`mbg-ami-fe`** (tunggu hingga status **Available**).

---

## Langkah 9: Target Group & Application Load Balancer

1. **Target Group (`mbg-tg-fe`)**:
   - Target type: **Instances**
   - Protocol: **HTTP** | Port: `80` | VPC: `mbg-vpc`
   - Health check path: `/health.php`

2. **Application Load Balancer (`mbg-alb-fe`)**:
   - Scheme: **Internet-facing** | IP address type: **IPv4**
   - VPC: `mbg-vpc`
   - Mappings: `mbg-subnet-public-alb-1a` dan `mbg-subnet-public-alb-1b`
   - Security Group: `mbg-sg-alb`
   - Listener: **HTTP:80** → Forward to `mbg-tg-fe`

---

## Langkah 10: Launch Template (`mbg-lt-fe`) & Auto Scaling Group (`mbg-asg-fe`)

1. **Launch Template (`mbg-lt-fe`)**:
   - AMI: **`mbg-ami-fe`** (dari Langkah 8)
   - Instance type: `t3.micro`
   - **Network settings → Auto-assign public IP**: **Disable** *(Wajib!)*
   - Security groups: `mbg-sg-fe`
   - **Resource tags**: Key = `Name`, Value = `mbg-ec2-fe` (Resource type: `Instances`)
   - **Advanced details → IAM instance profile**: `LabInstanceProfile`
   - **Advanced details → User data**: 👉 **[`scripts/launch-template-userdata.sh`](scripts/launch-template-userdata.sh)** *(ganti `EFS_ID` contoh `"fs-03504232a17c81d42"` dengan File System ID milikmu)*.

2. **Auto Scaling Group (`mbg-asg-fe`)**:
   - Launch template: `mbg-lt-fe` (Version: **Default / Latest**)
   - VPC: `mbg-vpc` | Subnets: `mbg-subnet-private-fe-1a` dan `mbg-subnet-private-fe-1b`
   - Load balancing: Attach to an existing load balancer → `mbg-tg-fe`
   - Health checks: Aktifkan **ELB** Health Checks (Grace period: `300s`)
   - Group size: Desired = `2`, Min = `2`, Max = `4`

---

## Langkah 11: Verifikasi Akhir

1. Pastikan kedua instance FE di Target Group `mbg-tg-fe` berstatus **Healthy**.
2. Akses **DNS Name ALB** di browser (contoh: `http://mbg-alb-fe-1940856405.us-east-1.elb.amazonaws.com`).
3. Uji login dengan 3 role (`bgn`, `sppg1`, `masy1` — password default: `123`), uji kirim aduan + upload foto (pastikan masuk ke S3 prefix `aduan/`), beri tanggapan sebagai `sppg1`, dan buat laporan (pastikan masuk ke S3 prefix `laporan/`).
4. Refresh halaman berulang kali untuk memastikan session EFS tidak ter-logout saat traffic berpindah antar instance FE.
