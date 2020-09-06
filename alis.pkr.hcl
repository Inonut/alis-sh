locals {
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  output_box = "./output_box"
}

source "virtualbox-iso" "arch_2020_08_01_x86_64" {
  guest_os_type = "ArchLinux_64"
  guest_additions_mode = "disable"
  headless = true
  http_directory = "srv"
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--memory", "2048"],
    ["modifyvm", "{{.Name}}", "--vram", "128"],
    ["modifyvm", "{{.Name}}", "--cpus", "2"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"]
  ]
  disk_size = 16384
  hard_drive_interface = "sata"
  iso_url = "https://mirror.rackspace.com/archlinux/iso/2020.08.01/archlinux-2020.08.01-x86_64.iso"
  iso_checksum = "sha1:50f6eeecd84aea8ea8cf3433fcc126eb396ed640"
  ssh_username = "${local.ssh_username}"
  ssh_password = "${local.ssh_password}"
  boot_wait = "30s"
  shutdown_command = "sudo systemctl poweroff"
  boot_command = [
    "/usr/bin/curl -O http://{{ .HTTPIP }}:{{ .HTTPPort }}/enable-ssh.sh<enter>",
    "/usr/bin/bash ./enable-ssh.sh ${local.ssh_username} ${local.ssh_password}<enter>"
  ]
}

build {
  sources = ["sources.virtualbox-iso.arch_2020_08_01_x86_64"]

  post-processor "vagrant" {
    output = "${local.output_box}/archlinux-alis-{{.BuildName}}.box"
  }

  post-processor "shell-local" {
    inline = ["echo 'Template build complete'"]
  }
}
