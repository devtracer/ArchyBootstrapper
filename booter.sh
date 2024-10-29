#!/bin/bash

# Synopsis: This script installs a base Arch Linux system to a specified disk.
# Proper usage: wget https://raw.githubusercontent.com/portalmaster137/ArchyBootstrapper/main/booter.sh -O booter.sh && chmod +x booter.sh && ./booter.sh

## STAGE 1: CONFIGURATION ##

# Determine if this is a UEFI or BIOS system
BIOS=false
UEFI=false

if [ -d "/sys/firmware/efi/efivars" ]; then
    if [ "$(cat /sys/firmware/efi/fw_platform_size)" -eq 32 ]; then
        echo "32-bit UEFI systems are not supported. Exiting."
        exit 1
    fi
    UEFI=true
    echo "UEFI system detected."
else
    BIOS=true
    echo "BIOS system detected."
fi

# Check for internet connection
if ! ping -c 1 google.com &> /dev/null; then
    echo "No internet connection detected."
    echo "Please set up your connection with iwctl or mmcli, then try again."
    echo "(DHCP will work automatically if using ethernet.)"
    exit 1
fi

# List available disks
lsblk

# Prompt user for installation parameters
echo "Enter the disk to install to (e.g., /dev/sda, /dev/nvme0n1):"
read -r DISK

echo "Enter the hostname of the system:"
read -r HOSTNAME

echo "Enter the username for the user account to be created:"
read -r USERNAME

# Prompt for timezone until valid
TIMEZONE=""
until [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; do
    echo "Enter your timezone (e.g., America/New_York):"
    read -r TIMEZONE
done

## STAGE 2: PARTITIONING ##

# Confirm partitioning
echo "The following disk will be partitioned: $DISK"
echo "This will erase all data on the disk."
read -p "Are you sure you want to continue? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" ]]; then
    echo "Aborting."
    exit 1
fi

# Validate disk existence and size
if [ ! -b "$DISK" ]; then
    echo "Disk $DISK does not exist."
    exit 1
fi

if [ "$(blockdev --getsize64 "$DISK")" -lt 15000000000 ]; then
    echo "Disk $DISK is too small. It must be at least 15GB."
    exit 1
fi

# Partition the disk
if [ "$BIOS" = true ]; then
    echo "Partitioning disk $DISK for BIOS system."
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary linux-swap 1MiB 513MiB
    parted -s "$DISK" mkpart primary ext4 513MiB 100%

    # Format partitions
    mkswap "${DISK}1"
    mkfs.ext4 "${DISK}2"

    # Mount partitions
    mount "${DISK}2" /mnt
    swapon "${DISK}1"

else
    echo "Partitioning disk $DISK for UEFI system."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart primary fat32 1MiB 1025MiB
    parted -s "$DISK" mkpart primary linux-swap 1025MiB 1537MiB
    parted -s "$DISK" mkpart primary ext4 1537MiB 100%

    # Format partitions
    mkfs.fat -F 32 "${DISK}1"
    mkswap "${DISK}2"
    mkfs.ext4 "${DISK}3"

    # Mount partitions
    mount "${DISK}3" /mnt
    swapon "${DISK}2"
    mkdir -p /mnt/boot
    mount "${DISK}1" /mnt/boot
fi

# Generate fstab
echo "Generating fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Update mirrorlist
echo "Updating mirrorlist."
reflector --latest 200 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 

## STAGE 3: INSTALLATION ##
echo "Installing base system."
pacstrap -k /mnt base linux linux-firmware sof-firmware networkmanager vim nano sudo grub efibootmgr elinks git reflector

echo "Base system installed."

## STAGE 4: SYSTEM CONFIGURATION ##
echo "Doing final configuration."
arch-chroot /mnt /bin/bash <<EOF
echo "$HOSTNAME" > /etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
systemctl enable NetworkManager

# Set root password
echo "Please enter the root password:"
read -s ROOT_PASSWORD
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user and set password
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "Please enter the password for user $USERNAME:"
read -s USER_PASSWORD
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install GRUB
if [ "$UEFI" = true ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK"
fi

grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Final configuration complete."

# Unmount partitions
umount -R /mnt

echo "Installation complete."
