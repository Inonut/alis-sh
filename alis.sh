#!/usr/bin/env bash
set -e
set -x

DEVICE="/dev/sda"
SWAP_SIZE="4096"
HOSTNAME="archlinux"
ROOT_PASSWORD="archlinux"
USER_NAME="dragos"
USER_PASSWORD="archlinux"

BOOT_MOUNT="/boot/efi"
SWAPFILE="/swapfile"
PARTITION_OPTIONS="defaults,noatime"
PARTITION_BOOT=""
PARTITION_ROOT=""

function last_partition_name() {
    local DEVICE=$1
    local last_partition=$(fdisk "$DEVICE" -l | tail -1)
    local last_partition_tokens=( $last_partition )
    local last_partition_name="${last_partition_tokens[0]}"

    echo $last_partition_name
}

function last_partition_end_mb() {
  local DEVICE="$1"
  local last_partition=$(parted "$DEVICE" unit MB print | tail -2)
  local last_partition_tokens=( $last_partition )
  local last_partition_memory="0%"
  if [[ "${last_partition_tokens[2]}" == *MB ]]; then
    last_partition_memory="${last_partition_tokens[2]}"
  fi

  echo $last_partition_memory
}

function packages_aur() {
  arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers

  arch-chroot /mnt pacman -Syu --noconfirm --needed git

  case "$1" in
    "aurman" )
      arch-chroot /mnt bash -c "echo -e \"$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n\" | su $USER_NAME -c \"cd /home/$USER_NAME && git clone https://aur.archlinux.org/$1.git && gpg --recv-key 465022E743D71E39 && (cd $1 && makepkg -si --noconfirm) && rm -rf $1\""
      ;;
    "yay" | *)
      arch-chroot /mnt bash -c "echo -e \"$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n\" | su $USER_NAME -c \"cd /home/$USER_NAME && git clone https://aur.archlinux.org/$1.git && (cd $1 && makepkg -si --noconfirm) && rm -rf $1\""
      ;;
  esac

  arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

loadkeys us
timedatectl set-ntp true

# only on ping -c 1, packer gets stuck if -c 5
ping -c 1 -i 2 -W 5 -w 30 "mirrors.kernel.org"
if [ $? -ne 0 ]; then
  echo "Network ping check failed. Cannot continue."
  exit
fi

parted $DEVICE mklabel gpt
parted $DEVICE mkpart primary 0% 512MiB
parted $DEVICE set 1 boot on
parted $DEVICE set 1 esp on
PARTITION_BOOT=$(last_partition_name $DEVICE)
parted $DEVICE mkpart primary 512MiB 100%
PARTITION_ROOT=$(last_partition_name $DEVICE)

mkfs.fat -n ESP -F32 $PARTITION_BOOT
mkfs.ext4 -L root $PARTITION_ROOT

mount -o $PARTITION_OPTIONS $PARTITION_ROOT /mnt
mkdir -p /mnt$BOOT_MOUNT
mount -o $PARTITION_OPTIONS $PARTITION_BOOT /mnt$BOOT_MOUNT

dd if=/dev/zero of=/mnt$SWAPFILE bs=1M count=$SWAP_SIZE status=progress
chmod 600 /mnt$SWAPFILE
mkswap /mnt$SWAPFILE

pacman -Sy --noconfirm reflector
reflector --country 'Romania' --latest 25 --age 24 --protocol https --completion-percent 100 --sort rate --save /etc/pacman.d/mirrorlist

pacstrap /mnt base base-devel linux linux-headers networkmanager xdg-user-dirs efibootmgr grub dosfstools virtualbox-guest-utils virtualbox-guest-dkms intel-ucode

genfstab -U /mnt >> /mnt/etc/fstab

echo "# swap" >> /mnt/etc/fstab
echo "$SWAPFILE none swap defaults 0 0" >> /mnt/etc/fstab
echo "" >> /mnt/etc/fstab

#sed -i 's/relatime/noatime/' /mnt/etc/fstab
arch-chroot /mnt systemctl enable fstrim.timer

arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Bucharest /etc/localtime
arch-chroot /mnt hwclock --systohc
LOCALES=(en_US.UTF-8 UTF-8 ro_RO.UTF-8 UTF-8)
LOCALE_CONF=(LANG=en_US.UTF-8)
for LOCALE in "${LOCALES[@]}"; do
  sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
  sed -i "s/#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
done
locale-gen
arch-chroot /mnt locale-gen
for VARIABLE in "${LOCALE_CONF[@]}"; do
  localectl set-locale "$VARIABLE"
  echo -e "$VARIABLE" >> /mnt/etc/locale.conf
done
echo -e "KEYMAP=us" > /mnt/etc/vconsole.conf
echo $HOSTNAME > /mnt/etc/hostname

printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd

arch-chroot /mnt mkinitcpio -P

arch-chroot /mnt systemctl enable NetworkManager.service

arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash $USER_NAME
printf "$USER_PASSWORD\n$USER_PASSWORD" | arch-chroot /mnt passwd $USER_NAME
arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

arch-chroot /mnt sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
arch-chroot /mnt sed -i 's/#GRUB_SAVEDEFAULT="true"/GRUB_SAVEDEFAULT="true"/' /etc/default/grub
arch-chroot /mnt sed -i -E 's/GRUB_CMDLINE_LINUX_DEFAULT="(.*) quiet"/GRUB_CMDLINE_LINUX_DEFAULT="\1"/' /etc/default/grub
echo "" >> /mnt/etc/default/grub
echo "# alis" >> /mnt/etc/default/grub
echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub
arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=$BOOT_MOUNT --recheck
arch-chroot /mnt grub-mkconfig -o "/boot/grub/grub.cfg"
echo -n "\EFI\grub\grubx64.efi" > "/mnt$BOOT_MOUNT/startup.nsh"

#arch-chroot /mnt pacman -Syu --noconfirm --needed xf86-video-intel mesa gnome
#arch-chroot /mnt systemctl enable gdm.service
#
#packages_aur yay

umount -R /mnt
