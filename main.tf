# Define the required OpenTofu provider
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.6.14"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Download Ubuntu Cloud Image
resource "null_resource" "download_image" {
  provisioner "local-exec" {
    command = "wget -nc -P ./images https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  }
}

# Define storage pool and volume for the VMs

resource "libvirt_volume" "image-webvm" {
  name   = "image-webvm.qcow2"
  pool   = "default"
  source = "./images/focal-server-cloudimg-amd64.img"
}

resource "libvirt_volume" "image-dbvm" {
  name   = "image-dbvm.qcow2"
  pool   = "default"
  source = "./images/focal-server-cloudimg-amd64.img"
}

resource "libvirt_volume" "webserver-volume" {
  name              = "webserver-volume.qcow2"
  pool              = "default"
  base_volume_name  = libvirt_volume.image-webvm.name
  base_volume_pool  = "default"
}

resource "libvirt_volume" "dbserver-volume" {
  name              = "dbserver-volume.qcow2"
  pool              = "default"
  base_volume_name  = libvirt_volume.image-dbvm.name
  base_volume_pool  = "default"
}


# Define cloud-init configuration
resource "libvirt_cloudinit_disk" "webserver-cloudinit" {
  name           = "webserver-cloudinit.iso"
  pool           = "default"
  user_data      = <<-EOF
  #cloud-config
    hostname: webserver
    users:
      - name: web
        groups: sudo
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        plain_text_passwd: "web"
        lock_passwd: false
        ssh_authorized_keys:
          - ${file("~/.ssh/id_rsa.pub")}
    runcmd:
      - apt-get update && apt-get install openssh-server -y
      - systemctl enable ssh
      - systemctl start ssh
    network:
      version: 2
      ethernets:
        ens3:
          dhcp4: false
          addresses:
            - 192.168.122.101/24
          gateway4: 192.168.122.1
          nameservers:
            addresses:
              - 8.8.8.8
    EOF
}

resource "libvirt_cloudinit_disk" "dbserver-cloudinit" {
  name           = "dbserver-cloudinit.iso"
  pool           = "default"
  user_data      = <<-EOF
  #cloud-config
    hostname: dbserver
    users:
      - name: db
        groups: sudo
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        plain_text_passwd: "db"
        lock_passwd: false
        ssh_authorized_keys:
          - ${file("~/.ssh/id_rsa.pub")}
    runcmd:
      - apt-get update && apt-get install openssh-server -y
      - systemctl enable ssh
      - systemctl start ssh
    network:
      version: 2
      ethernets:
        ens3:
          dhcp4: false
          addresses:
            - 192.168.122.102/24
          gateway4: 192.168.122.1
          nameservers:
            addresses:
              - 8.8.8.8
    EOF
}


# Define and create the VMs
resource "libvirt_domain" "webvm" {
  name      = "webvm"
  memory    = 2048
  vcpu      = 2
  cloudinit = libvirt_cloudinit_disk.webserver-cloudinit.id

  network_interface {
    network_name = "default"
    hostname     = "webserver"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.webserver-volume.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "virtio"
  }

  graphics {
    type = "vnc"
    listen_type = "address"
    listen_address = "0.0.0.0"
    autoport = true
  }

}

resource "libvirt_domain" "dbvm" {
  name      = "dbvm"
  memory    = 2048
  vcpu      = 2
  cloudinit = libvirt_cloudinit_disk.dbserver-cloudinit.id

  network_interface {
    network_name = "default"
    hostname     = "dbserver"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.dbserver-volume.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "virtio"
  }

  graphics {
    type = "vnc"
    listen_type = "address"
    listen_address = "0.0.0.0"
    autoport = true
  }

}


# Output IP addresses of the VMs
output "webvm_ip" {
  value = libvirt_domain.webvm.network_interface.0.addresses[0]
}

output "dbvm_ip" {
  value = libvirt_domain.dbvm.network_interface.0.addresses[0]
}
