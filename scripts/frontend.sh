#!/bin/bash
# ==============================================================================
# SCRIPT SETUP FRONT END (mbg-ec2-fe-temp / Pre-Prod AMI)
# ==============================================================================
# GANTI VARIABEL BERIKUT SESUAI AKUN & INFRASTRUKTUR KAMU:
EFS_ID="GANTI_DENGAN_EFS_ID"
BE_PRIVATE_IP="GANTI_DENGAN_PRIVATE_IP_BE"
# ==============================================================================

set -e

echo "=== 1. Set Hostname & Install Paket (termasuk botocore & boto3 untuk EFS) ==="
hostnamectl set-hostname mbg-ec2-fe
dnf update -y
dnf install -y php php-cli php-mbstring php-curl git httpd amazon-efs-utils nfs-utils composer python3-botocore python3-boto3
systemctl start httpd
systemctl enable httpd

echo "=== 2. Mount EFS Shared Session (${EFS_ID}) ==="
mkdir -p /mnt/efs/mbg-session
for i in {1..15}; do
  mount -t efs -o tls ${EFS_ID}:/ /mnt/efs/mbg-session && break || sleep 5
done

if ! grep -q "/mnt/efs/mbg-session" /etc/fstab; then
  echo "${EFS_ID}:/ /mnt/efs/mbg-session efs _netdev,tls 0 0" >> /etc/fstab
fi

chown -R apache:apache /mnt/efs/mbg-session
chmod 777 /mnt/efs/mbg-session

echo "=== 3. Clone Source Code Front End ==="
cd /var/www/html
rm -rf * .* 2>/dev/null || true
git clone https://github.com/ukkce2627/mbg-app-fe .

echo "=== 4. Buat File config.php Front End ==="
cat << EOF_CONFIG > /var/www/html/config.php
<?php
return [
    'api_base_url'      => 'http://${BE_PRIVATE_IP}/api',
    'api_key'           => 'mbg-secret-key-2024',
    'session_save_path' => '/mnt/efs/mbg-session',
];
EOF_CONFIG

echo "=== 5. Konfigurasi PHP Session ke EFS ==="
sed -i 's|;session.save_path = "/tmp"|session.save_path = "/mnt/efs/mbg-session"|g' /etc/php.ini
sed -i 's|session.save_path = "/var/lib/php/session"|session.save_path = "/mnt/efs/mbg-session"|g' /etc/php.ini
echo 'session.save_path = "/mnt/efs/mbg-session"' > /etc/php.d/99-session.ini

echo "=== 6. Patch Tautan Lampiran pada views/sppg/aduan.php ==="
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
    print('aduan.php patched successfully')
EOF_P1

echo "=== 7. Patch Status Lowercase pada includes/helpers.php ==="
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
    print('helpers.php patched successfully')
EOF_P2

echo "=== 8. Konfigurasi Permissions & Apache AllowOverride All ==="
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
systemctl restart httpd

echo "=== SELESAI SETUP FRONT END! ==="
