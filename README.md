# Panduan Membangun Infrastruktur Multi-Tier High Availability di AWS

Panduan langkah demi langkah untuk membangun arsitektur aplikasi web multi-tier (*Front End*, *Back End*, *Database*, *Shared Session*, *Object Storage*, dan *Notification*) dengan keamanan jaringan privat dan skalabilitas otomatis di AWS Region **`us-east-1`**.

---

## Persiapan Awal
- Pastikan seluruh resource dibuat di Region **`us-east-1` (N. Virginia)**.
- Catat **AWS Account ID** kamu di awal untuk penamaan S3 Bucket dan SNS Topic ARN.

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

3. Tunggu sampai status **Available**, lalu catat **Endpoint RDS**.

---

## Langkah 5: S3 Bucket & SNS Topic

1. **S3 Bucket**:
   - Bucket name (Account Regional): `mbg-uploads-<ACCOUNT_ID>-us-east-1-an`
   - Region: `us-east-1`
   - **Block all public access**: Centang semua (Aktif).
   - Buat 2 folder/prefix di dalam bucket: `aduan/` dan `laporan/`.

2. **SNS Topic & Subscription**:
   - Buat Topic bertipe **Standard** dengan nama `mbg-sns-notifikasi`.
   - Buat Subscription: Protocol **Email**, Endpoint: `ukkce2627@smkn1bms.sch.id`.
   - Pastikan status subscription sudah **Confirmed**. Catat **Topic ARN**.

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

2. Masukkan script berikut ke **User Data** (atau jalankan via SSM Session Manager), sesuaikan `RDS_HOST`, `S3_BUCKET`, dan `SNS_TOPIC_ARN`:

```bash
#!/bin/bash
RDS_HOST="GANTI_DENGAN_ENDPOINT_RDS"
DB_USER="admin"
DB_PASS="12345678"
DB_NAME="mbg_db"
S3_BUCKET="mbg-uploads-GANTI_ACCOUNT_ID-us-east-1-an"
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:GANTI_ACCOUNT_ID:mbg-sns-notifikasi"
AWS_REGION="us-east-1"

set -e
hostnamectl set-hostname mbg-ec2-be
dnf update -y
dnf install -y php php-cli php-mysqlnd php-xml php-mbstring php-curl php-zip unzip git httpd composer awscli
systemctl start httpd
systemctl enable httpd

aws s3api put-object --bucket "${S3_BUCKET}" --key aduan/ --region "${AWS_REGION}" || true
aws s3api put-object --bucket "${S3_BUCKET}" --key laporan/ --region "${AWS_REGION}" || true

# Setup Swap 2GB agar composer tidak kehabisan RAM di t3.micro
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=128M count=16
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

cd /var/www/html
rm -rf * .* 2>/dev/null || true
git clone https://github.com/ukkce2627/mbg-app-be .

export COMPOSER_ALLOW_SUPERUSER=1
export COMPOSER_MEMORY_LIMIT=-1
for i in {1..5}; do
  php -d memory_limit=-1 /usr/bin/composer require aws/aws-sdk-php --no-interaction --prefer-dist && break || sleep 5
done

cat << EOF_CONFIG > /var/www/html/config.php
<?php
return [
    'db' => [
        'host' => '${RDS_HOST}',
        'port' => '3306',
        'user' => '${DB_USER}',
        'pass' => '${DB_PASS}',
        'name' => '${DB_NAME}',
    ],
    's3' => [
        'bucket' => '${S3_BUCKET}',
        'region' => '${AWS_REGION}',
    ],
    'sns' => [
        'topic_arn' => '${SNS_TOPIC_ARN}',
    ],
    'api_key' => 'mbg-secret-key-2024',
];
EOF_CONFIG

# Bersihkan fallback storage lokal
rm -rf /var/www/html/public/storage/* 2>/dev/null || true
touch /var/www/html/public/storage/.gitkeep
chown -R apache:apache /var/www/html
chmod -R 775 /var/www/html

sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
systemctl restart httpd

# Auto-migration & seed akun awal
for i in {1..30}; do
  php /var/www/html/seed_users.php && break || sleep 5
done
```

3. Catat **Private IP** dari `mbg-ec2-be` setelah instance berjalan.

---

## Langkah 8: EC2 Front End Sementara & Pembuatan AMI (`mbg-ami-fe`)

1. Launch EC2 sementara (`mbg-ec2-fe-temp`):
   - AMI: **Amazon Linux 2023** | Instance type: `t3.micro`
   - Subnet: `mbg-subnet-private-fe-1a` | Auto-assign public IP: **Disable**
   - Security Group: `mbg-sg-fe` | IAM instance profile: `LabInstanceProfile`

2. Masukkan script berikut ke **User Data** (ganti `EFS_ID` dan `BE_PRIVATE_IP`):

```bash
#!/bin/bash
EFS_ID="GANTI_DENGAN_EFS_ID"
BE_PRIVATE_IP="GANTI_DENGAN_PRIVATE_IP_BE"

set -e
hostnamectl set-hostname mbg-ec2-fe
dnf update -y
dnf install -y php php-cli php-mbstring php-curl git httpd amazon-efs-utils nfs-utils composer python3-botocore python3-boto3
systemctl start httpd
systemctl enable httpd

# Mount EFS Shared Session
mkdir -p /mnt/efs/mbg-session
for i in {1..15}; do
  mount -t efs -o tls ${EFS_ID}:/ /mnt/efs/mbg-session && break || sleep 5
done
if ! grep -q "/mnt/efs/mbg-session" /etc/fstab; then
  echo "${EFS_ID}:/ /mnt/efs/mbg-session efs _netdev,tls 0 0" >> /etc/fstab
fi
chown -R apache:apache /mnt/efs/mbg-session
chmod 777 /mnt/efs/mbg-session

cd /var/www/html
rm -rf * .* 2>/dev/null || true
git clone https://github.com/ukkce2627/mbg-app-fe .

cat << EOF_CONFIG > /var/www/html/config.php
<?php
return [
    'api_base_url'      => 'http://${BE_PRIVATE_IP}/api',
    'api_key'           => 'mbg-secret-key-2024',
    'session_save_path' => '/mnt/efs/mbg-session',
];
EOF_CONFIG

# Arahkan PHP session ke EFS
sed -i 's|;session.save_path = "/tmp"|session.save_path = "/mnt/efs/mbg-session"|g' /etc/php.ini
sed -i 's|session.save_path = "/var/lib/php/session"|session.save_path = "/mnt/efs/mbg-session"|g' /etc/php.ini
echo 'session.save_path = "/mnt/efs/mbg-session"' > /etc/php.d/99-session.ini

# Patch tautan 'Lihat lampiran' pada aduan.php
python3 - << 'EOF_P1'
p1 = '/var/www/html/views/sppg/aduan.php'
with open(p1, 'r') as f:
    c = f.read()
if 'Lihat lampiran' not in c:
    target = 'Klik foto untuk memperbesar.</div>'
    replacement = 'Klik foto untuk memperbesar.</div>\n          <p><a class="btn btn-sm btn-outline-primary" href="<?= fe_e($a[\'file_url\']) ?>" target="_blank" rel="noopener">Lihat lampiran</a></p>'
    c = c.replace(target, replacement)
    with open(p1, 'w') as f:
        f.write(c)
EOF_P1

# Patch status lowercase pada helpers.php
python3 - << 'EOF_P2'
p2 = '/var/www/html/includes/helpers.php'
with open(p2, 'r') as f:
    c2 = f.read()
target2 = "fe_e(ucfirst($status)) . '</span>'"
replacement2 = "fe_e(ucfirst($status)) . '</span> <span class=\"d-none\">' . strtolower($status) . '</span>'"
if 'strtolower($status)' not in c2:
    c2 = c2.replace(target2, replacement2)
    with open(p2, 'w') as f:
        f.write(c2)
EOF_P2

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
systemctl restart httpd
```

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
   - **Advanced details → User data** (ganti `EFS_ID`):

```bash
#!/bin/bash
EFS_ID="GANTI_DENGAN_EFS_ID"

hostnamectl set-hostname mbg-ec2-fe
mkdir -p /mnt/efs/mbg-session
for i in {1..10}; do
  mount -t efs -o tls ${EFS_ID}:/ /mnt/efs/mbg-session && break || sleep 5
done
if ! grep -q "/mnt/efs/mbg-session" /etc/fstab; then
  echo "${EFS_ID}:/ /mnt/efs/mbg-session efs _netdev,tls 0 0" >> /etc/fstab
fi
chown -R apache:apache /mnt/efs/mbg-session
chmod 777 /mnt/efs/mbg-session
systemctl start httpd
systemctl enable httpd
```

2. **Auto Scaling Group (`mbg-asg-fe`)**:
   - Launch template: `mbg-lt-fe` (Version: **Default / Latest**)
   - VPC: `mbg-vpc` | Subnets: `mbg-subnet-private-fe-1a` dan `mbg-subnet-private-fe-1b`
   - Load balancing: Attach to an existing load balancer → `mbg-tg-fe`
   - Health checks: Aktifkan **ELB** Health Checks (Grace period: `300s`)
   - Group size: Desired = `2`, Min = `2`, Max = `4`

---

## Langkah 11: Verifikasi Akhir

1. Pastikan kedua instance FE di Target Group `mbg-tg-fe` berstatus **Healthy**.
2. Akses **DNS Name ALB** di browser.
3. Uji login dengan 3 role (`bgn`, `sppg1`, `masy1` — password default: `123`), uji kirim aduan + upload foto (pastikan masuk ke S3 prefix `aduan/`), beri tanggapan sebagai `sppg1`, dan buat laporan (pastikan masuk ke S3 prefix `laporan/`).
4. Refresh halaman berulang kali untuk memastikan session EFS tidak ter-logout saat traffic berpindah antar instance FE.
