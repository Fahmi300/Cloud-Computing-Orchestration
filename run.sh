#!/bin/bash

# Update system packages and install required software
# sudo apt-get update
# sudo apt-get install -y libvirt-daemon-system libvirt-clients selinux-basics selinux-policy-default genisoimage

# # Activate SELinux (if necessary)
# sudo selinux-activate

# Start and enable libvirt service
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# Add the current user to the libvirt and kvm groups
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)

# Ensure the libvirt-qemu user has access to images directory
sudo usermod -aG kvm libvirt-qemu
sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/images
sudo chmod -R 775 /var/lib/libvirt/images

# Restart libvirtd to apply changes
sudo systemctl restart libvirtd

# Define and start a storage pool
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default

# Clean up existing VMs and their disks
for vm in $(virsh list --all --name); do
    virsh undefine $vm
    disk=$(virsh dumpxml $vm | grep "source file" | sed -e 's/.*source file=.//' -e 's/.//g')
    if [ -n "$disk" ]; then
        rm -f "$disk"
    fi
done

# Disable AppArmor if active
if sudo systemctl is-active --quiet apparmor; then
    sudo systemctl stop apparmor
    sudo systemctl disable apparmor
    APPARMOR_DISABLED=1
else
    APPARMOR_DISABLED=0
fi

# Disable SELinux if it is active
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "Disabling SELinux temporarily..."
    sudo setenforce 0
    SELINUX_DISABLED=1
else
    SELINUX_DISABLED=0
fi

# Run Terraform (OpenTofu) to apply the configuration
tofu apply
