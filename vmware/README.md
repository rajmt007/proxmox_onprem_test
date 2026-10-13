# VMware Workstation / Player preparation

The Ansible playbooks manage Proxmox only after both Proxmox VE operating systems have been installed. They do not select or wipe VMware disks or silently run an OS installer.

## Create the VM shells manually

In VMware, create two **new** VMs from the official Proxmox VE ISO. Check each VM name and virtual disk path first. Installation can erase the selected virtual disk; do not reuse or overwrite an existing VM.

| Setting | Node 1 | Node 2 |
|---|---|---|
| VM name | pve01 | pve02 |
| Static address | 192.168.1.111 | 192.168.1.112 |
| Network | Bridged to the correct lab LAN or a documented isolated network | Same reachable L2/L3 network |
| Virtualization | Enable nested VT-x/EPT or AMD-V/RVI | Same |

Choose CPU, RAM, disk, subnet prefix, gateway, and DNS from your physical host's capacity and actual network plan. Do not assume the gateway. Confirm that both requested IPs are reserved/free using Envir plus router/DHCP/IPAM checks. Enable virtualization in host BIOS/UEFI.

Install Proxmox VE on each VM. Set unique hostnames, the requested IP addresses and correct subnet/gateway/DNS values. Verify SSH access, verify host keys through a trusted channel and add them to the Ansible controller's known_hosts. The controller needs SSH and TCP 8006 access to both nodes.

Before running Ansible, confirm:
- both Proxmox versions are compatible;
- hostnames/IPs/name resolution and time sync are correct;
- node-to-node ping works in both directions;
- nested KVM virtualization is exposed and usable;
- neither node is already part of an unrelated cluster;
- enough storage is available for the Windows and Ubuntu guests.

Then follow ../ansible/README.md, starting with the read-only preflight playbook.
