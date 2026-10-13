# Master Prompt: Build and Validate a Two-Node Proxmox Lab

You are a senior virtualization, Windows/Linux, VMware, Proxmox VE, automation, and GitHub DevOps engineer. **Execute the work in the repository; do not return only a plan, sample snippets, or a UI mock-up.** Build a documented, testable repository that prepares a nested Proxmox lab on VMware Workstation Player/Workstation, validates two Proxmox nodes, forms a cluster only when pre-checks pass, deploys one Windows VM and one Ubuntu VM, tests guest-to-guest connectivity, and publishes all source files to the GitHub repository below.

## Repository target

- Git remote: https://github.com/rajmt007/proxmox_onprem_test.git
- Repository name: proxmox_onprem_test
- Inspect the existing repository, default branch, tree, working state, and permissions first. Preserve unrelated files and local changes. Never force-push, overwrite user changes, or commit secrets.
- If authentication is unavailable, prepare and validate local files and provide exact safe push commands. Never claim a push succeeded unless the remote confirms it.

## Required outcome

1. Inspect the environment inventory workbook and worksheet named Envir before creating machines or assigning IPs.
2. Use VMware Player/Workstation to prepare two new VMs for Proxmox VE, if host nested virtualization supports it.
3. Configure Proxmox node 1 at 192.168.1.111 (suggested hostname pve01) and node 2 at 192.168.1.112 (suggested hostname pve02).
4. Verify network connectivity both ways and Proxmox installation readiness with explicit PASS, FAIL, BLOCKED, or NOT RUN results and evidence.
5. Form a cluster only after all required pre-checks pass. Verify membership, quorum, node state, storage, networking, and time synchronization.
6. Deploy exactly one Windows VM and one Ubuntu VM on the healthy Proxmox cluster using official installation media and non-conflicting VM IDs/IPs.
7. Test connectivity in both directions between Windows and Ubuntu and publish the real results.
8. Validate code and documentation, then push to this repository if authenticated access is available.

## Safety rules

- Proxmox installation is destructive to the selected VM disk. Before installation, show the VM name, disk path/size, ISO, target IP, and inventory matches. Require explicit confirmation. Never wipe, repartition, reinstall, delete, or repurpose a machine silently.
- Treat the Envir worksheet as inventory, not proof an IP is free. Check repository records, ARP/neighbour data, ping, and any available DHCP/router reservation data. A failed ping alone does not prove an IP is unused. If a conflict is found or availability cannot be established, stop; do not silently change requested IPs.
- If the workbook or Envir sheet is missing, search for inventory files. If none exists, create a documented inventory template with an Envir worksheet and mark values as proposed/unknown. Do not invent gateway, prefix, DNS, VLAN, storage, credentials, or guest IPs. Block environment-changing steps until required values are supplied.
- Never commit passwords, API tokens, private keys, Windows product keys, real host inventory, or sensitive logs. Use environment variables, SSH keys, ignored local files, or a supported secret store. Provide .env.example with placeholders only.
- Do not disable host, Proxmox, or guest firewalls wholesale to make ping work. If needed, request approval for a narrowly scoped ICMP rule. Distinguish firewall-blocked ICMP from network failure.
- Do not use pvecm expected 1 as a permanent quorum fix. Two voting nodes can lose quorum when one is down. Document this limitation and recommend a QDevice or third voting node. Do not claim high availability merely because a two-node cluster forms.
- Use Windows media from the user or official Microsoft sources; never embed a license key. Verify Ubuntu media checksum against official Ubuntu values.
- Provide dry-run/preflight modes and require approval before destructive or environment-changing phases. Do not run cleanup/destroy automatically.

## Stage 0 — Repository and inventory

1. Inspect the repository and report current branch, default branch, working tree/tree contents, and remote access.
2. Search for .xlsx, .xlsm, .csv, .json, and documented inventory sources. Read Envir if present. Record the worksheet columns, matching hostnames/IPs, VM IDs, and relevant network details.
3. Check whether 192.168.1.111 and 192.168.1.112 already belong to another machine, as well as existing VMware VM folders or Proxmox nodes. If a conflict exists, report it and stop provisioning.
4. If no Envir worksheet exists, create inventory/environment-inventory.xlsx with an Envir sheet and these columns: MachineName, Role, Hypervisor, IP_Address, Subnet_Prefix, Gateway, DNS, VLAN_or_Network, VM_ID, OS, Status, Owner, Last_Checked, Notes. Preserve existing inventory. Mark newly created rows as proposals until confirmed.

## Stage 1 — Host preflight and VMware

Detect the host OS and installed VMware tools. Check VMware Player/Workstation availability, CPU/RAM/disk capacity, Intel VT-x/AMD-V, and whether nested virtualization is exposed to guests. If the installed edition cannot be reliably controlled through CLI, provide safe manual UI steps rather than inventing commands.

Create configurable definitions for the two Proxmox VMs. Use names pve01 and pve02, and the required static IPs. CPU, RAM, disk size, ISO path, network adapter mode, subnet prefix, gateway, and DNS must be configurable. Use inventory values or ask for missing network data; do not assume the gateway is 192.168.1.1. Check physical-host resource availability before provisioning. Explain that Proxmox inside VMware is a nested lab, not the recommended production topology.

Use the currently supported official Proxmox installation approach for the chosen version. Prefer an officially supported unattended install/answer-file method only after verifying its current documentation. Otherwise create VM shells and provide precise manual installation steps. A VM or mounted ISO does not prove Proxmox is installed.

## Stage 2 — Node readiness and connectivity

After installation and explicit approval, validate each node:

- SSH/API reachability and Proxmox version.
- Hostname and name resolution between pve01 and pve02.
- IP address and correct interface/bridge.
- Gateway reachability if a gateway is supplied.
- Bidirectional ping and neighbour-table checks where available.
- Time synchronization.
- Nested KVM/virtualization availability inside each Proxmox node.
- No unrelated cluster membership.
- No duplicate hostname or IP.

Write reports/proxmox-preflight.md and machine-readable JSON/CSV results. Each test must include status (PASS/FAIL/BLOCKED/NOT RUN), timestamp, command/test, concise output, and remediation. Any failed prerequisite blocks cluster creation.

## Stage 3 — Cluster readiness and formation

Before creating a cluster, confirm compatible Proxmox versions, stable IPs and hostnames, mutual name resolution, required Corosync network reachability, synchronized time, no existing cluster membership, and no workloads/data that would be overwritten. Print the checklist and require explicit approval.

If pre-checks pass and approval is received:

1. Create the cluster on pve01 using commands/API supported by the installed version.
2. Join pve02 through the supported command/API and secure authentication.
3. Verify members, quorum, online node state, Corosync links, storage, and networks.
4. If creation/join fails, stop and report diagnostics. Do not loop destructive join/reset actions.
5. Explain that a basic two-vote cluster requires both nodes to be online to retain quorum in normal conditions. Recommend a QDevice or third voting node before relying on availability.

Write reports/cluster-status.md and JSON/CSV. Guest deployment stays blocked unless both nodes and cluster/quorum checks are healthy.

## Stage 4 — Windows and Ubuntu guest VMs

Only after a healthy cluster is confirmed, create two guests through the Proxmox API or a maintained Terraform provider. Pin provider versions, validate current documentation, and never hard-code credentials.

- Windows: use a user-provided or official Microsoft ISO. Configure suitable CPU, RAM, disk, firmware, machine type, and VirtIO drivers. If Windows 11 is selected, validate TPM/Secure Boot requirements. Do not embed product keys. Clearly document interactive installer steps unless a safe user-provided unattended file is available.
- Ubuntu: use an official Ubuntu Server ISO/cloud image and verify its checksum/signature. Prefer cloud-init for hostname, first user/SSH public key, static IP, and initial configuration when supported.
- Before creating guests, check VM IDs, names, IPs, storage and bridge use. Guest IPs must be configurable and must not overlap Proxmox node IPs or inventory IPs. If guest addressing is missing, prepare definitions but pause deployment.
- Make guest CPU/RAM/disk configurable. Never guess free storage or select a destructive target silently.

Report VM ID, name, node, power state, guest-agent status if installed, address if known, and remaining manual steps.

## Stage 5 — Guest network tests

Test Ubuntu-to-Windows and Windows-to-Ubuntu connectivity from inside the guests where possible:

1. Interface and IP/subnet configuration.
2. Neighbour/ARP resolution where applicable.
3. Gateway reachability where relevant.
4. ICMP Echo in both directions.
5. Optional TCP service test only with user approval.

If Windows Firewall blocks inbound ICMP, explain this and request approval before adding a narrowly scoped Echo rule for the lab subnet. Never disable the firewall globally. Report PASS, FAIL, or BLOCKED_BY_FIREWALL with timestamp, source/destination, method, latency/loss when available, and diagnostic notes. Save to reports/guest-connectivity.md and JSON/CSV.

## Required repository structure

Create a clear layout, adapting to a better existing convention where appropriate:

    proxmox_onprem_test/
    ├── README.md
    ├── PROMPT.md
    ├── .gitignore
    ├── .env.example
    ├── config/
    │   ├── lab.example.yaml
    │   └── vm-specs.example.yaml
    ├── inventory/
    │   ├── README.md
    │   └── environment-inventory.xlsx (only if no Envir sheet exists)
    ├── scripts/
    │   ├── preflight.ps1
    │   ├── preflight.sh
    │   ├── check-ip-conflicts.ps1
    │   ├── check-proxmox-nodes.sh
    │   ├── configure-cluster.sh
    │   ├── deploy-guests.sh
    │   ├── test-guest-connectivity.ps1
    │   └── test-guest-connectivity.sh
    ├── terraform/ (if API/provider automation is feasible)
    │   ├── versions.tf
    │   ├── variables.tf
    │   ├── providers.tf
    │   ├── main.tf
    │   ├── outputs.tf
    │   └── README.md
    ├── tests/
    │   ├── README.md
    │   └── test-config-validation.*
    └── reports/
        ├── .gitkeep
        └── README.md

Do not add empty scripts that pretend to work. Validate required credentials, host-specific values, and media inputs, and return actionable errors when missing.

## Code quality and test requirements

- Use clear functions, validation, strict error handling, non-zero exit codes on failure, and useful logs.
- Make actions idempotent where feasible. Preflight and report scripts must not mutate infrastructure. Detect existing objects before create/update.
- Add dry-run/preflight and explicit confirmation gates for all destructive or environment-changing phases.
- Test missing inventory/sheet, IP conflict detection, invalid network data, missing secrets, existing VM IDs, failed ping, failed quorum, and deployment blocking. Use mocks/sample data so tests run without a live cluster.
- Use current official VMware, Proxmox, and provider docs. Pin dependencies and document safe updates.
- .gitignore must exclude .env, Terraform state, downloaded ISOs, VM disks, private keys, sensitive generated reports, and logs.

## GitHub publication

1. Review git diff and git status. Ensure no secrets, downloaded media, disks, Terraform state, or unrelated changes are committed.
2. Run tests/validation and document results. Never mark unrun tests as passed.
3. Commit project changes using a clear message such as: feat: add Proxmox two-node lab automation.
4. Push to the intended branch without force-push. If remote changes exist, fetch and reconcile them safely.
5. Verify the remote commit URL, branch, commit hash, files changed, tests run, and blocked/manual steps.
6. If authorization is missing, do not ask the user to paste secrets into chat. Leave local files intact and provide safe authentication/push commands.

## Final acceptance checklist

Answer each item with evidence and exact status:

- Was the repository and Envir worksheet inspected?
- Were target IP conflicts checked and found safe to proceed?
- Were VMware host requirements and nested virtualization validated?
- Are 192.168.1.111 and 192.168.1.112 reachable both ways?
- Did both Proxmox nodes pass readiness?
- Is the cluster healthy; what are quorum and QDevice status?
- Were exactly one Windows guest and one Ubuntu guest created without VM ID/IP/storage conflict?
- Was guest connectivity tested both directions, with actual results?
- Which commands/tests passed, failed, were blocked, or were not run?
- Was the commit pushed and verified? Supply a real commit URL only if confirmed.

**Begin by inspecting the repository and inventory. Do not skip preflight, invent network settings, or claim provisioning success without live command output.**