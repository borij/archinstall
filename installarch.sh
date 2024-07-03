#!/bin/bash

set -e
# Начальные настройки
loadkeys ru
setfont cyr-sun16
timedatectl set-ntp true
timedatectl set-timezone Europe/Moscow
reflector --verbose --download-timeout 10 --country Russia --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

# Проверка прав суперпользователя
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт нужно запускать от имени суперпользователя (root)." >&2
  exit 1
fi

# Выбор диска
echo "Доступные диски:"
lsblk -d -n -o NAME,SIZE
read -rp "Введите диск для установки (например, /dev/sda): " DISK

# Проверка, существует ли диск
if [ ! -b "$DISK" ]; then
  echo "Указанный диск не существует." >&2
  exit 1
fi

# Разметка диска
sgdisk -Z "$DISK"         # Обнуление диска
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"  # EFI раздел
sgdisk -n 2:0:0 -t 2:8300 "$DISK"      # Корневой раздел

# Форматирование разделов
mkfs.fat -F32 "${DISK}1"  # EFI раздел
mkfs.btrfs "${DISK}2"     # Корневой раздел

# Монтирование разделов и создание подтомов
mount "${DISK}2" /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots
umount /mnt

# Монтирование подтомов
mount -o noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@ "${DISK}2" /mnt
mkdir -p /mnt/{boot,home,.snapshots}
mount -o noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@home "${DISK}2" /mnt/home
mount -o noatime,compress=lzo,space_cache=v2,discard=async,ssd,subvol=@snapshots "${DISK}2" /mnt/.snapshots
mount "${DISK}1" /mnt/boot

# Установка базовой системы
pacstrap /mnt base linux linux-firmware btrfs-progs vim

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Настройка системы
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" > /etc/vconsole.conf

echo "archlinux" > /etc/hostname
echo "127.0.0.1	localhost" >> /etc/hosts
echo "::1	localhost" >> /etc/hosts
echo "127.0.1.1	archlinux.localdomain	archlinux" >> /etc/hosts

pacman -S --noconfirm grub efibootmgr networkmanager bluez bluez-utils gnome gnome-extra mesa wpa_supplicant dialog os-prober mtools dosfstools ntfs-3g nano iwd curl wget git linux-headers amd-ucode network-manager-applet

mkinitcpio -p linux

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

fallocate -l 10G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab

systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable gdm

EOF