#!/bin/bash
# ==============================================================================
# USER DATA LAUNCH TEMPLATE (mbg-lt-fe)
# ==============================================================================
# GANTI EFS_ID DENGAN FILE SYSTEM ID KAMU:
EFS_ID="GANTI_DENGAN_EFS_ID"
# ==============================================================================

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
