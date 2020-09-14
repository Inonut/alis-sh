locals {
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  output_box = "./output_box"
  arch_version = "{{isotime \"2006.01\"}}"
}

source "virtualbox-iso" "arch-linux" {
  guest_os_type = "ArchLinux_64"
  guest_additions_mode = "disable"
  headless = false
  http_directory = "."
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--memory", "2048"],
    ["modifyvm", "{{.Name}}", "--vram", "128"],
    ["modifyvm", "{{.Name}}", "--cpus", "2"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"]
  ]
  disk_size = 16384
  hard_drive_interface = "sata"
  iso_url = "https://mirror.rackspace.com/archlinux/iso/${local.arch_version}.01/archlinux-${local.arch_version}.01-x86_64.iso"
  iso_checksum = "file:https://mirrors.kernel.org/archlinux/iso/${local.arch_version}.01/sha1sums.txt"
  ssh_username = "${local.ssh_username}"
  ssh_password = "${local.ssh_password}"
  boot_wait = "30s"
  shutdown_command = "sudo systemctl poweroff"
  boot_command = [
    "/usr/bin/curl -O http://{{ .HTTPIP }}:{{ .HTTPPort }}/alis.sh<enter>",
    "chmod +x ./alis.sh<enter>",
    "./alis.sh<enter><wait1>",
    "/usr/bin/curl -O http://{{ .HTTPIP }}:{{ .HTTPPort }}/srv/enable-ssh.sh<enter>",
    "/usr/bin/bash ./enable-ssh.sh ${local.ssh_username} ${local.ssh_password}<enter>",
  ]
}

build {
  sources = ["sources.virtualbox-iso.arch-linux"]

  post-processor "vagrant" {
    output = "${local.output_box}/alis-{{ .Provider }}-${local.arch_version}.box"
  }
}
