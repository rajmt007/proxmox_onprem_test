# Proxmox Two-Node Nested Lab (VMware Workstation)

A safety-first automation scaffold for preparing two nested Proxmox VE nodes, validating the LAN and host prerequisites, forming a cluster only after checks pass, and defining one Windows plus one Ubuntu guest. **The repo does not claim that a VM, Proxmox installation, cluster, or guest exists until live scripts have run and recorded evidence.**

## Current state

- The `Envir` worksheet exists in `inventory/environment-inventory.xlsx`.
- The requested addresses `192.168.1.111` and `192.168.1.112` are marked **PROPOSED**. They have not been checked against your DHCP/router reservations or physical LAN.
- All host/network-changing scripts default to inspection or dry-run; installation, cluster formation, and guest deployment require explicit flags and typed confirmation.
- Live Proxmox, VMware, DHCP, and guest connectivity checks have not been run from the repository-building environment.

## Prerequisites

1. A supported 64-bit Windows host with VMware Workstation Player/Workstation and hardware virtualization enabled in firmware. Confirm that your VMware build supports exposing VT-x/AMD-V to the nested guest. This is a nested lab; it is not the preferred production Proxmox deployment model.
2. Enough host RAM, CPU, and free disk for both Proxmox VMs **plus** the Windows and Ubuntu guests. The sizing values in the YAML files are examples; resize to the real host capacity.
3. Official Proxmox VE ISO media, a supported Windows ISO sourced from Microsoft, and an official Ubuntu Server ISO. Verify the Ubuntu checksum against the published value for the exact release.
4. Verified subnet prefix, gateway, DNS, network/VLAN, VMware adapter mode, Proxmox bridge, storage target, guest addresses, and two unused guest VM IDs. Do not infer these from the requested node IP range.
5. SSH public-key authentication from the management machine to both Proxmox nodes. Do not put passwords or API tokens in repository files.
6. Python 3.10+ for validation. Python tests use the standard library. `PyYAML` is only needed when you use YAML-loading extensions or choose to add them.

## Fast start (safe checks only)

Run these from a fresh working copy on the actual Windows host/LAN. Commands below do not install Proxmox or create guests.

### 1. Inventory and configuration

```powershell
Copy-Item config/lab.example.yaml config/lab.yaml
Copy-Item config/vm-specs.example.yaml config/vm-specs.yaml
Copy-Item .env.example .env
# Edit the local files with verified values; never commit config/lab.yaml, config/vm-specs.yaml, or .env.
python scripts/inventory_check.py --path inventory/environment-inventory.xlsx --worksheet Envir --target-ip 192.168.1.111 --target-ip 192.168.1.112
```

Review every row. The target IPs are not considered free if inventory matching, neighbor evidence, or a live response suggests a conflict. A failed ping alone leaves availability **unknown**. Independently confirm the addresses in your router/DHCP reservation system.

### 2. Windows host preflight

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\preflight.ps1 -ReportPath reports/generated/host-preflight.json
.\scripts\check-ip-conflicts.ps1 -TargetIP 192.168.1.111,192.168.1.112 -ReportDirectory reports/generated
```

A result of `UNKNOWN_BLOCKED` means stop, not “free.” The script cannot query your router/DHCP reservations unless you add a supported integration for that platform.

### 3. Prepare the VMware shells (manual UI supported)

Use VMware Workstation UI to create two **new** VMs named `pve01` and `pve02`; connect each to the verified LAN/network and enable **Virtualize Intel VT-x/EPT or AMD-V/RVI** in Processor settings. Attach the official Proxmox ISO. Keep a separate, clearly named virtual disk for each node. Review the VM name, disk path/size, ISO, and requested target IP before starting the installer.

Do not select an existing VM disk. Proxmox installation erases the selected target disk. Stop if either IP is in use or cannot be confidently cleared for this lab.

### 4. Install and check the Proxmox nodes

Before each installation, run the destructive-disk review helper in a separate PowerShell session and complete the typed confirmation:

```powershell
.\scripts\authorize-proxmox-install.ps1 -VMName pve01 -VMFolder 'D:\VMs\pve01' -TargetIP 192.168.1.111 -ConfirmTargetIpAvailability
.\scripts\authorize-proxmox-install.ps1 -VMName pve02 -VMFolder 'D:\VMs\pve02' -TargetIP 192.168.1.112 -ConfirmTargetIpAvailability
```

Replace those example folder paths with the exact folders printed by your earlier shell-creation step. Then install Proxmox interactively into the dedicated virtual disks. Use the verified network values; assign `pve01` / `192.168.1.111` and `pve02` / `192.168.1.112` only after the conflicts have been resolved. Configure name resolution consistently between nodes.

From a management host with SSH access:

```bash
chmod +x scripts/*.sh
scripts/check-proxmox-nodes.sh
```

The report must show all required checks `PASS` before cluster creation is eligible. Save the generated live report only after reviewing it for sensitive information.

### 5. Create the cluster only after readiness checks pass

Set the variables from verified values in your shell, then run the safe preflight mode first:

```bash
export PVE01_HOST=pve01 PVE02_HOST=pve02
export PVE01_IP=192.168.1.111 PVE02_IP=192.168.1.112
export PVE_SSH_USER=root
export CLUSTER_NAME="<choose-a-unique-cluster-name>"
# After filling the guest settings in your ignored .env file:
set -a; source .env; set +a
scripts/configure-cluster.sh
```

The no-argument invocation is a preflight only. Once you have reviewed all live checks and the exact cluster name, use the explicit apply gate:

```bash
scripts/configure-cluster.sh --apply --confirm-cluster-creation
```

The script stops on the first failed precondition or failed cluster/join command. For this new lab, it blocks cluster formation if either node already has a VM or container; do not repurpose a node with existing workloads. It does not repeatedly attempt resets or use `pvecm expected 1` as a permanent workaround.

**Two-node quorum note:** A two-vote cluster commonly loses quorum when one node is unavailable. Do not assume high availability from a successful cluster formation. Add a QDevice or a third voting node before relying on availability-sensitive workloads.

### 6. Deploy the guest VMs

Guest deployment is blocked until all values are verified: Windows/Ubuntu ISO filenames already uploaded to the intended Proxmox storage, storage ID, bridge, unused VM IDs, unique guest IPs, subnet prefix, and gateway. Add these values to local `.env` (ignored by Git) using your actual environment. The script checks cluster quorum and collisions again. Set `PVE_STORAGE` to the verified VM-disk storage and `PVE_ISO_STORAGE` to a storage that supports ISO media; these can be different.

```bash
set -a; source .env; set +a
scripts/deploy-guests.sh --dry-run
# After reviewing the plan and confirming all required values:
scripts/deploy-guests.sh --apply --confirm-guest-deployment
```

The guest definitions attach official install media and create VM shells; OS setup remains interactive unless you deliberately supply and review a supported unattended answer file/cloud-init configuration. Windows licensing is your responsibility. Windows 11 also requires the selected virtual firmware, Secure Boot, and TPM configuration to satisfy its requirements.

### 7. Guest-to-guest connectivity and reports

Use `scripts/test-guest-connectivity.sh` from a management host configured for SSH access to both guests, or `scripts/test-guest-connectivity.ps1` from a Windows host. ICMP results can be `BLOCKED_BY_FIREWALL`; the scripts do not disable firewalls. If required, approve a narrowly scoped inbound Echo rule for the lab subnet and test again.

Reports are written under `reports/generated/` and are gitignored by default. Never describe a `NOT RUN` or `BLOCKED` check as passed.

## Tests and validation

```bash
python -m unittest discover -s tests -v
python scripts/inventory_check.py --path inventory/environment-inventory.xlsx --worksheet Envir --target-ip 192.168.1.111 --target-ip 192.168.1.112
bash -n scripts/preflight.sh scripts/check-proxmox-nodes.sh scripts/configure-cluster.sh scripts/deploy-guests.sh scripts/test-guest-connectivity.sh
```

The tests use mocks/sample records and do not connect to your LAN. A passed unit test is not proof that VMware nesting, node networking, cluster quorum, or guest connectivity work in your environment.

## Project layout

```text
config/                 Example lab and guest YAML (no local secrets)
inventory/              Envir workbook and usage notes
scripts/                Host, inventory, node, cluster, guest, and connectivity checks
terraform/              Pinned provider example; configure only after API/network preflight
tests/                  Offline safety/unit tests
reports/                Sanitized documentation; generated live reports are ignored
```

## Official references

- Proxmox VE Administration Guide: https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf
- Proxmox VE installation downloads: https://www.proxmox.com/en/downloads
- VMware Workstation documentation: https://docs.vmware.com/en/VMware-Workstation-Pro/index.html
- Microsoft Windows download and installation media: https://www.microsoft.com/software-download/
- Ubuntu Server downloads and checksum verification: https://ubuntu.com/download/server
- bpg Proxmox Terraform provider and versioned documentation: https://registry.terraform.io/providers/bpg/proxmox/0.112.0/docs

## Limitations

This execution environment cannot access your physical LAN or VMware host, and direct `git` networking is unavailable here. Repository access/publication through the connected GitHub account is handled separately. Actual installation, IP conflict clearance, node readiness, cluster quorum, guest creation, and guest connectivity remain pending live execution on your lab machine.
