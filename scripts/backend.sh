#!/bin/bash
# ==============================================================================
# SCRIPT SETUP BACK END (mbg-ec2-be)
# ==============================================================================
# CONTOH FORMAT VARIABEL (Ganti sesuai Endpoint RDS & Account ID milikmu):
RDS_HOST="mbg-rds-mysql.c1fa8qkqs4ma.us-east-1.rds.amazonaws.com"        # <-- Ganti dengan Endpoint RDS milikmu
DB_USER="admin"
DB_PASS="12345678"
DB_NAME="mbg_db"
S3_BUCKET="mbg-uploads-937385515130-us-east-1-an"                        # <-- Ganti 937385515130 dengan Account ID milikmu
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:937385515130:mbg-sns-notifikasi"    # <-- Ganti 937385515130 dengan Account ID milikmu
AWS_REGION="us-east-1"
# ==============================================================================

set -e

echo "=== 1. Set Hostname & Install Paket ==="
hostnamectl set-hostname mbg-ec2-be
dnf update -y
dnf install -y php php-cli php-mysqlnd php-xml php-mbstring php-curl php-zip unzip git httpd composer awscli
systemctl start httpd
systemctl enable httpd

echo "=== 2. Buat Folder Prefix S3 (aduan/ dan laporan/) ==="
aws s3api put-object --bucket "${S3_BUCKET}" --key aduan/ --region "${AWS_REGION}" || true
aws s3api put-object --bucket "${S3_BUCKET}" --key laporan/ --region "${AWS_REGION}" || true

echo "=== 3. Setup Swap 2GB (Cegah OOM Saat Composer Require di t3.micro) ==="
if [ ! -f /swapfile ]; then
  dd if=/dev/zero of=/swapfile bs=128M count=16
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

echo "=== 4. Clone Source Code Back End ==="
cd /var/www/html
rm -rf * .* 2>/dev/null || true
git clone https://github.com/ukkce2627/mbg-app-be .

echo "=== 5. Install AWS SDK for PHP via Composer ==="
export COMPOSER_ALLOW_SUPERUSER=1
export COMPOSER_MEMORY_LIMIT=-1
for i in {1..5}; do
  php -d memory_limit=-1 /usr/bin/composer require aws/aws-sdk-php --no-interaction --prefer-dist && break || sleep 5
done

echo "=== 6. Buat File config.php ==="
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

echo "=== 7. Bersihkan Local Fallback Storage ==="
rm -rf /var/www/html/public/storage/* 2>/dev/null || true
touch /var/www/html/public/storage/.gitkeep
chown -R apache:apache /var/www/html
chmod -R 775 /var/www/html

echo "=== 8. Konfigurasi Apache AllowOverride All ==="
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
systemctl restart httpd

echo "=== 9. Jalankan Auto-Migration & Seed User Awal ==="
for i in {1..30}; do
  php /var/www/html/seed_users.php && break || sleep 5
done

echo "=== SELESAI SETUP BACK END! ==="
