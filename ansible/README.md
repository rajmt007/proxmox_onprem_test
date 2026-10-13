# Ansible automation for the Proxmox lab

These playbooks begin after Proxmox VE has been installed on two VMware VMs and the nodes use these addresses:

- pve01 — 192.168.1.111
- pve02 — 192.168.1.112

They do not silently install an OS or erase a VM disk. Cluster formation and guest deployment require separate explicit approvals.

## 1. Install the controller dependencies

Use Linux or Ubuntu on WSL with network access to SSH/TCP 8006 on both Proxmox nodes, plus SSH to Ubuntu and WinRM HTTPS to Windows for guest tests.

From the repository root:

```bash
cd ansible
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
cp .env.example .env
chmod 600 .env
```

Edit `.env` locally, then load it before running commands:

```bash
set -a
. ./.env
set +a
```

Never commit `.env`, passwords, tokens, private keys, or real inventory files. SSH host-key checking remains enabled; verify host keys through a trusted channel and add them to known_hosts.

## 2. Inventory workbook and IP checks

Provide the real workbook containing an `Envir` worksheet. Set `ENVIR_WORKBOOK` to its absolute path. The checker detects common machine/IP column names.

To generate an empty template (this does NOT prove IP availability):

```bash
python scripts/check_envir_inventory.py --create-template --workbook inventory/environment-inventory.xlsx
```

Fill the workbook with verified environment data. A clean spreadsheet is not proof an IP is available; also verify router/DHCP/IPAM reservations and live conflicts. A missing or empty Envir sheet blocks environment-changing stages.

## 3. Read-only preflight

Review `inventory/hosts.yml`. The default SSH user is root; set `PVE_SSH_USER` in .env if needed and configure SSH key authentication.

```bash
python scripts/validate_env.py --stage preflight
ansible-inventory --graph
ansible-playbook playbooks/preflight.yml
```

The playbook checks SSH, Proxmox version, hostname, IP assignment, peer ping, NTP synchronization, and nested-virtualization flags. It writes `reports/ansible-preflight.json`. Do not proceed until failures have been resolved.

## 4. Create the two-node cluster

Before cluster creation, make sure both nodes are freshly installed, have matching Proxmox releases, hostnames/IPs are correct, clocks are synchronized, ping works in both directions, and neither node has existing cluster configuration. Confirm required Corosync connectivity and the Envir inventory.

```bash
python scripts/validate_env.py --stage cluster
ansible-playbook playbooks/cluster.yml -e "cluster_create_enabled=true cluster_change_approval=CREATE-TWO-NODE-CLUSTER"
```

Cluster operations are disabled by default. The playbook refuses nodes with an existing `/etc/pve/corosync.conf`; if a run is interrupted after creating the cluster, stop and inspect the cluster rather than deleting files or retrying blindly.

The Proxmox cluster join operation needs an authorized master-node password in addition to API credentials in the installed community.proxmox collection interface. Keep `PROXMOX_MASTER_PASSWORD` only in the untracked local .env. The account must have appropriate permissions.

Two voting nodes can lose quorum when one node is down. Consider a QDevice or third voting node for a more resilient quorum design. This lab is not automatically high availability.

## 5. Configure and deploy the guests

Set these values in local .env:
- `PROXMOX_USER`, `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`
- `PVE_VM_STORAGE`, `PVE_ISO_STORAGE`, `PVE_BRIDGE`
- `WINDOWS_ISO_NAME`, `WINDOWS_VIRTIO_ISO_NAME`, `UBUNTU_ISO_NAME`
- `WINDOWS_GUEST_IP`, `UBUNTU_GUEST_IP`
- `ENVIR_WORKBOOK` and `IP_RESERVATIONS_CONFIRMED=true` only after review

The ISOs must already be on the configured Proxmox ISO storage and visible to the target node. Use an official Microsoft ISO and official Ubuntu media; verify the Ubuntu checksum. Default VM IDs are 120 (Windows on pve01) and 121 (Ubuntu on pve02); inspect the live cluster and change them if already used.

```bash
python scripts/validate_env.py --stage deploy
ansible-playbook playbooks/deploy_guests.yml -e "guest_deploy_enabled=true guest_deploy_approval=DEPLOY-WINDOWS-UBUNTU-VMs"
```

This playbook creates and starts the VM shells but does not complete interactive Windows/Ubuntu installers or insert a product key. Use the Proxmox console to finish OS installation, configure the documented guest IPs, enable SSH/WinRM HTTPS, and install/configure guest agents as needed.

## 6. Test guest-to-guest ping

After the OS installs, set `WINDOWS_GUEST_IP`, `UBUNTU_GUEST_IP`, `WINRM_USER`, `WINRM_PASSWORD`, `UBUNTU_SSH_USER`, and `UBUNTU_SSH_KEY` in .env. Windows WinRM HTTPS must be configured and certificate-trusted by the controller.

```bash
python scripts/validate_env.py --stage connectivity
ansible-playbook playbooks/connectivity.yml
```

It tests Ubuntu-to-Windows and Windows-to-Ubuntu ping from inside the guest OSs and writes `reports/guest-connectivity.json`. If ICMP fails, examine addressing, subnet/routing, virtual bridge and firewall rules. Do not disable firewalls globally; scope any Echo rule narrowly.

## Syntax checks

```bash
ansible-playbook playbooks/preflight.yml --syntax-check
ansible-playbook playbooks/cluster.yml --syntax-check
ansible-playbook playbooks/deploy_guests.yml --syntax-check
ansible-playbook playbooks/connectivity.yml --syntax-check
python scripts/check_envir_inventory.py --help
python scripts/validate_env.py --help
```

Syntax checks do not contact Proxmox. A successful syntax check is not proof that cluster creation, guest installation, or ping tests succeeded.
