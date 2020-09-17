#!/usr/bin/env bash
set -e

WARNING="Please run with --generate-defaults option. \nDo needed changes in alis.conf before continue. \nAlso run with --help for more details."

function last_partition_name() {
  local DEVICE=$1
  local last_partition=$(fdisk "$DEVICE" -l | tail -1)
  local last_partition_tokens=($last_partition)
  local last_partition_name="${last_partition_tokens[0]}"

  echo $last_partition_name
}

function last_partition_end_mb() {
  local DEVICE="$1"
  local last_partition=$(parted "$DEVICE" unit MB print | tail -2)
  local last_partition_tokens=($last_partition)
  local last_partition_memory="0%"
  if [[ "${last_partition_tokens[2]}" == *MB ]]; then
    last_partition_memory="${last_partition_tokens[2]}"
  fi

  echo $last_partition_memory
}

function yay() {
  local PASS=$1
  printf "%s\n" "$PASS" | sudo --stdin pacman -S --noconfirm git
  git clone https://aur.archlinux.org/yay.git
  cd yay
  printf "%s\n" "$PASS" | makepkg -si --noconfirm
  cd ..
  rm -rf yay
}

function install_arch_uefi() {
  if [ ! -f alis.conf ]; then
    echo -e $WARNING
    exit 1
  else

    for line in `cat alis.conf`
    do
      if [ -n "$line" ]; then
        eval "local $line"
      fi
    done

    local FEATURES=$1
    local SWAPFILE="/swapfile"
    local PARTITION_OPTIONS="defaults,noatime"
    local PARTITION_BOOT=""
    local PARTITION_ROOT=""
  fi

  loadkeys us
  timedatectl set-ntp true

  # only on ping -c 1, packer gets stuck if -c 5
  ping -c 1 -i 2 -W 5 -w 30 "mirrors.kernel.org"
  if [ $? -ne 0 ]; then
    echo "Network ping check failed. Cannot continue."
    exit
  fi

  sgdisk --zap-all $DEVICE
  wipefs -a $DEVICE

  parted $DEVICE mklabel gpt
  parted $DEVICE mkpart primary 0% 512MiB
  parted $DEVICE set 1 boot on
  parted $DEVICE set 1 esp on # this flag identifies a UEFI System Partition. On GPT it is an alias for boot.
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

  VIRTUALBOX=""
  if [ -n "$(lspci | grep -i virtualbox)" ]; then
    VIRTUALBOX="virtualbox-guest-utils virtualbox-guest-dkms intel-ucode"
  fi
  pacstrap /mnt base base-devel linux linux-headers networkmanager efibootmgr grub $VIRTUALBOX

  genfstab -U /mnt >>/mnt/etc/fstab

  echo "# swap" >>/mnt/etc/fstab
  echo "$SWAPFILE none swap defaults 0 0" >>/mnt/etc/fstab
  echo "" >>/mnt/etc/fstab

  arch-chroot /mnt systemctl enable fstrim.timer

  arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Bucharest /etc/localtime
  arch-chroot /mnt hwclock --systohc
  sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo -e "LANG=en_US.UTF-8" >>/mnt/etc/locale.conf
  echo -e "KEYMAP=us" >/mnt/etc/vconsole.conf
  echo $HOSTNAME >/mnt/etc/hostname

  printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd

  arch-chroot /mnt mkinitcpio -P

  arch-chroot /mnt systemctl enable NetworkManager.service

  arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash $USER_NAME
  printf "$USER_PASSWORD\n$USER_PASSWORD" | arch-chroot /mnt passwd $USER_NAME
  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /mnt/etc/sudoers

  sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /mnt/etc/default/grub
  sed -i "s/#GRUB_SAVEDEFAULT=\"true\"/GRUB_SAVEDEFAULT=\"true\"/" /mnt/etc/default/grub
  arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=$BOOT_MOUNT --recheck
  arch-chroot /mnt grub-mkconfig -o "/boot/grub/grub.cfg"
  if [ -n "$(lspci | grep -i virtualbox)" ]; then
    echo -n "\EFI\grub\grubx64.efi" >"/mnt$BOOT_MOUNT/startup.nsh"
  fi

  mv alis.sh /mnt/home/$USER_NAME
  arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
  arch-chroot /mnt bash -c "echo -e \"$USER_PASSWORD\n\" | su $USER_NAME -c \"cd /home/$USER_NAME && ./alis.sh ${FEATURES[*]}\""
  arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

  umount -R /mnt
}


DEFAULT_OPTIONS='
DEVICE="/dev/sda"
SWAP_SIZE="4096"
HOSTNAME="archlinux"
ROOT_PASSWORD="archlinux"
USER_NAME="admin"
USER_PASSWORD="admin"
BOOT_MOUNT="/boot/efi"
'

usage="

Script for installing Arch Linux and configure applications

options:
    --help                Show this help text
    --generate-defaults   Generate file alis.conf (!!! DO THIS FIRST !!!)
    --install-arch-uefi   Install Arch Linux in uefi mode, this erase all of your data
    --all-packages        Install all available packages
    --yay                 Install yay, tool for installing packages from AUR

"

if [[ "$*" =~ "-v" ]]; then
  set -x
fi

if [[ "$*" =~ "-h" ]] || [[ "$*" =~ "--help" ]]; then
  echo "$usage"
  exit 1
fi

if [[ "$*" =~ "--generate-defaults" ]]; then
  echo "$DEFAULT_OPTIONS" > alis.conf
  echo "File alis.conf was created!"
  exit 1
fi

if [[ "$*" =~ "--install-arch-uefi" ]]; then
  FEATURES=()
  for feature in "$@"
  do
    if [ $feature != "--install-arch-uefi" ]; then
      FEATURES+=($feature)
    fi
  done
  install_arch_uefi ${FEATURES[*]}
else
  read -p "Password: " -s password
  echo ""

  FEATURES=()
  if [[ "$*" =~ "--all-packages" ]]; then
    FEATURES=(--yay)
  else
    FEATURES=$@
  fi

  for feature in $FEATURES
  do
    case "$feature" in
      --yay )
        yay $password
        ;;
    esac
  done
fi
