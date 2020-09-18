#!/usr/bin/env bash
set -e

WARNING="Please run with --generate-defaults option. \nDo needed changes in alis.conf before continue. \nAlso run with --help for more details."

function warning_service() {
  local service="$1"
  echo "Warning: $service service will start after reboot!"
}

function read_variables() {
  local variable_list="$1"
  if [[ ! -f alis.conf ]]; then
    echo -e "$WARNING"
    exit 1
  else

    while IFS= read -r line
    do
      if [[ -n "$line" ]] && [[ "$variable_list" =~ $(echo "$line" | awk -v FS='(|=)' '{print $1}') ]]; then
        eval "$line"
      fi
    done < <(grep -v '^ *#' < alis.conf)
  fi
}

function last_partition_name() {
  local DEVICE="$1"
  local last_partition
  local last_partition_tokens

  last_partition=$(fdisk "$DEVICE" -l | tail -1)
  IFS=" " read -r -a last_partition_tokens <<< "$last_partition"

  echo "${last_partition_tokens[0]}"
}

function last_partition_end_mb() {
  local DEVICE="$1"
  local last_partition
  local last_partition_tokens

  last_partition=$(parted "$DEVICE" unit MB print | tail -2)
  IFS=" " read -r -a last_partition_tokens <<< "$last_partition"
  if [[ "${last_partition_tokens[2]}" == *MB ]]; then
    echo "${last_partition_tokens[2]}"
  else
    echo "0%"
  fi
}

function yay() {
  sudo pacman -S --noconfirm git
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
}

function ssh() {
  sudo pacman -S --noconfirm openssh
  sudo systemctl enable sshd.service
  { # try
    sudo systemctl start sshd.service
  } || { # catch
    warning_service sshd
  }
}

function gnome() {
  sudo pacman -S --noconfirm gnome gnome-extra
  sudo systemctl enable gdm.service
  { # try
    sudo systemctl start gdm.service
  } || { # catch
    warning_service gdm
  }
}

function install_arch_uefi() {
  local FEATURES=( "$@" )
  local SWAPFILE="/swapfile"
  local PARTITION_OPTIONS="defaults,noatime"
  local PARTITION_BOOT
  local PARTITION_ROOT
  local DEVICE
  local SWAP_SIZE
  local HOSTNAME
  local ROOT_PASSWORD
  local USER_NAME
  local USER_PASSWORD
  local BOOT_MOUNT
  read_variables "$(declare -p | grep 'declare --' | awk -v FS='(--|=)' '{print $2}')"

  loadkeys us
  timedatectl set-ntp true

  # only on ping -c 1, packer gets stuck if -c 5
  local ping
  ping=$(ping -c 1 -i 2 -W 5 -w 30 "mirrors.kernel.org")
  if [[ "$ping" == 0 ]]; then
    echo "Network ping check failed. Cannot continue."
    exit
  fi

  sgdisk --zap-all "$DEVICE"
  wipefs -a "$DEVICE"

  parted "$DEVICE" mklabel gpt
  parted "$DEVICE" mkpart primary 0% 512MiB
  parted "$DEVICE" set 1 boot on
  parted "$DEVICE" set 1 esp on # this flag identifies a UEFI System Partition. On GPT it is an alias for boot.
  PARTITION_BOOT=$(last_partition_name "$DEVICE")
  parted "$DEVICE" mkpart primary 512MiB 100%
  PARTITION_ROOT=$(last_partition_name "$DEVICE")

  mkfs.fat -n ESP -F32 "$PARTITION_BOOT"
  mkfs.ext4 -L root "$PARTITION_ROOT"

  mount -o $PARTITION_OPTIONS "$PARTITION_ROOT" /mnt
  mkdir -p /mnt"$BOOT_MOUNT"
  mount -o $PARTITION_OPTIONS $PARTITION_BOOT /mnt"$BOOT_MOUNT"

  dd if=/dev/zero of=/mnt"$SWAPFILE" bs=1M count="$SWAP_SIZE" status=progress
  chmod 600 /mnt"$SWAPFILE"
  mkswap /mnt"$SWAPFILE"

  pacman -Sy --noconfirm reflector
  reflector --country 'Romania' --latest 25 --age 24 --protocol https --completion-percent 100 --sort rate --save /etc/pacman.d/mirrorlist

  VIRTUALBOX=""
  if lspci | grep -q -i virtualbox; then
    VIRTUALBOX=(virtualbox-guest-utils virtualbox-guest-dkms intel-ucode)
  fi
  pacstrap /mnt base base-devel linux linux-headers networkmanager efibootmgr grub "${VIRTUALBOX[@]}"

  {
    genfstab -U /mnt
    echo "# swap"
    echo "$SWAPFILE none swap defaults 0 0"
    echo ""
  } >> /mnt/etc/fstab

  arch-chroot /mnt systemctl enable fstrim.timer

  arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Bucharest /etc/localtime
  arch-chroot /mnt hwclock --systohc
  sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo -e "LANG=en_US.UTF-8" >>/mnt/etc/locale.conf
  echo -e "KEYMAP=us" >/mnt/etc/vconsole.conf
  echo "$HOSTNAME" >/mnt/etc/hostname

  printf "%s\n%s\n" "$ROOT_PASSWORD" "$ROOT_PASSWORD" | arch-chroot /mnt passwd

  arch-chroot /mnt mkinitcpio -P

  arch-chroot /mnt systemctl enable NetworkManager.service

  arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash "$USER_NAME"
  printf "%s\n%s\n" "$USER_PASSWORD" "$USER_PASSWORD" | arch-chroot /mnt passwd "$USER_NAME"
  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /mnt/etc/sudoers

  sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /mnt/etc/default/grub
  sed -i "s/#GRUB_SAVEDEFAULT=\"true\"/GRUB_SAVEDEFAULT=\"true\"/" /mnt/etc/default/grub
  arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory="$BOOT_MOUNT" --recheck
  arch-chroot /mnt grub-mkconfig -o "/boot/grub/grub.cfg"
  if lspci | grep -q -i virtualbox; then
    echo -n "\EFI\grub\grubx64.efi" >"/mnt$BOOT_MOUNT/startup.nsh"
  fi

  mv alis.sh /mnt/home/"$USER_NAME"
  sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /mnt/etc/sudoers
  arch-chroot /mnt bash -c "su $USER_NAME -c \"cd /home/$USER_NAME && ./alis.sh ${FEATURES[*]}\""
  sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers

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

usage='

Script for installing Arch Linux and configure applications

options:
    --help                Show this help text
    --generate-defaults   Generate file alis.conf
    --install-arch-uefi   Install Arch Linux in uefi mode, this erase all of your data
    --all-packages        Install all available packages
    --yay                 Install yay, tool for installing packages from AUR
    --ssh                 Configure ssh
    --gnome               Install gnome as user interface

'
ARGS=( "$@" )
FEATURES=()

function remove_el_from_args() {
  for i in "${!ARGS[@]}"; do
    if [[ "${ARGS[$i]}" = "$1" ]]; then
      unset "ARGS[$i]"
    fi
  done
}

if [[ "${ARGS[*]}" =~ -v ]]; then
  set -x
fi

if [[ "${ARGS[*]}" =~ -h ]] || [[ "${ARGS[*]}" =~ --help ]]; then
  echo "$usage"
  exit 1
fi

if [[ "${ARGS[*]}" =~ --generate-defaults ]]; then
  echo "$DEFAULT_OPTIONS" > alis.conf
  echo "File alis.conf was created!"
  exit 1
fi

if [[ "${#ARGS[@]}" == 0 ]]; then
  exit 1
fi

if [[ "${ARGS[*]}" =~ --install-arch-uefi ]]; then
  remove_el_from_args --install-arch-uefi
  install_arch_uefi "${ARGS[@]}"
else
  if [[ "${ARGS[*]}" =~ --all-packages ]]; then
    FEATURES=(--yay --ssh --gnome)
  else
    FEATURES=("${ARGS[@]}")
  fi

  for feature in "${FEATURES[@]}"
  do
    case "$feature" in
      --yay )
        yay
        ;;
      --ssh )
        ssh
        ;;
      --gnome )
        gnome
        ;;
    esac
  done
fi
