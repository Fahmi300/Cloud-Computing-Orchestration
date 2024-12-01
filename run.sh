#!/bin/bash

#installation
# sudo apt-get update
# sudo apt-get install -y libvirt-daemon-system libvirt-clients selinux-basics selinux-policy-default genisoimage

# # Activate SELinux (if necessary)
# sudo selinux-activate

# Start and enable libvirt service
echo "Starting and enabling libvirt service..."
sudo systemctl start libvirtd
sudo systemctl enable libvirtd

# Add the current user and libvirt-qemu to the necessary groups
echo "Configuring user and group permissions..."
sudo usermod -aG libvirt $(whoami)
sudo usermod -aG kvm $(whoami)
sudo usermod -aG kvm libvirt-qemu

# Set permissions for the libvirt images directory
echo "Setting permissions for /var/lib/libvirt/images..."
sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/images
sudo chmod -R 775 /var/lib/libvirt/images

# Restart libvirt service to apply changes
echo "Restarting libvirt service..."
sudo systemctl restart libvirtd


# Storage Pool Configuration
echo "Defining and starting the default storage pool..."
virsh pool-define-as default dir --target /var/lib/libvirt/images
virsh pool-build default
virsh pool-start default
virsh pool-autostart default


# Cleanup Existing Virtual Machines
echo "Cleaning up existing virtual machines and disks..."
for vm in $(virsh list --all --name); do
    echo "Undefining VM: $vm"
    virsh undefine "$vm"
    
    disk=$(virsh dumpxml "$vm" | grep "source file" | sed -e 's/.*source file=.//' -e 's/.//g')
    if [ -n "$disk" ]; then
        echo "Removing disk: $disk"
        rm -f "$disk"
    fi
done

# Disable AppArmor if active
if sudo systemctl is-active --quiet apparmor; then
    echo "Disabling AppArmor..."
    sudo systemctl stop apparmor
    sudo systemctl disable apparmor
    APPARMOR_DISABLED=1
else
    APPARMOR_DISABLED=0
fi

# Disable SELinux temporarily if active
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    echo "Disabling SELinux temporarily..."
    sudo setenforce 0
    SELINUX_DISABLED=1
else
    SELINUX_DISABLED=0
fi

# Remove any existing Ansible inventory file
echo "Cleaning up Ansible inventory file..."
sudo rm -f ansible_inventory.ini

# Apply Terraform (OpenTofu) configuration
echo "Applying Terraform (OpenTofu) configuration..."
tofu apply

# Run Ansible playbooks for webserver and dbserver setup
echo "Running Ansible playbooks..."
ansible-playbook -i ansible_inventory.ini setup/webserver-setup.yaml
ansible-playbook -i ansible_inventory.ini setup/dbserver-setup.yaml

echo "Setup completed!"