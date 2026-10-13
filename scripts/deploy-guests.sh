#!/usr/bin/env bash
# Creates exactly one Windows VM and one Ubuntu VM only after all safety gates pass.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PVE01_HOST="${PVE01_HOST:-pve01}"; PVE02_HOST="${PVE02_HOST:-pve02}"
PVE_SSH_USER="${PVE_SSH_USER:-root}"
PVE01_IP="${PVE01_IP:-192.168.1.111}"; PVE02_IP="${PVE02_IP:-192.168.1.112}"
APPLY=0; CONFIRM_FLAG=0
for arg in "$@"; do case "$arg" in --apply) APPLY=1;; --confirm-guest-deployment) CONFIRM_FLAG=1;; --dry-run) APPLY=0;; --help|-h) echo 'Usage: deploy-guests.sh [--dry-run | --apply --confirm-guest-deployment]'; exit 0;; *) echo "Unknown argument $arg" >&2; exit 64;; esac; done
required=(WINDOWS_VMID UBUNTU_VMID WINDOWS_GUEST_IP UBUNTU_GUEST_IP SUBNET_PREFIX GATEWAY VM_BRIDGE PVE_STORAGE PVE_ISO_STORAGE WINDOWS_ISO UBUNTU_ISO WINDOWS_NODE UBUNTU_NODE WINDOWS_DISK_GIB WINDOWS_RAM_MIB WINDOWS_VCPU UBUNTU_DISK_GIB UBUNTU_RAM_MIB UBUNTU_VCPU WINDOWS_OS_TYPE WINDOWS_GUEST_NAME UBUNTU_GUEST_NAME)
missing=()
for name in "${required[@]}"; do [[ -n "${!name:-}" ]] || missing+=("$name"); done
if ((${#missing[@]})); then echo "BLOCKED: required verified values missing: ${missing[*]}" >&2; exit 2; fi
if [[ "${GUEST_IP_AVAILABILITY_CONFIRMED:-NO}" != 'YES' ]]; then echo 'BLOCKED: confirm DHCP/router reservation and inventory checks by setting GUEST_IP_AVAILABILITY_CONFIRMED=YES only after checking them.' >&2; exit 2; fi
for v in VM_BRIDGE PVE_STORAGE PVE_ISO_STORAGE WINDOWS_NODE UBUNTU_NODE; do if [[ ! "${!v}" =~ ^[A-Za-z0-9_.+-]+$ ]]; then echo "BLOCKED: $v contains unsupported characters. Use a verified plain Proxmox bridge/storage/node identifier." >&2; exit 2; fi; done
for v in WINDOWS_DISK_GIB WINDOWS_RAM_MIB WINDOWS_VCPU UBUNTU_DISK_GIB UBUNTU_RAM_MIB UBUNTU_VCPU; do if [[ ! "${!v}" =~ ^[0-9]+$ ]] || (( ${!v} < 1 )); then echo "BLOCKED: $v must be a positive integer." >&2; exit 2; fi; done
if [[ "$WINDOWS_VMID" == "$UBUNTU_VMID" ]]; then echo 'BLOCKED: Windows and Ubuntu VM IDs must differ.' >&2; exit 2; fi
for v in WINDOWS_VMID UBUNTU_VMID; do if [[ ! "${!v}" =~ ^[0-9]+$ ]] || (( ${!v} < 100 || ${!v} > 999999999 )); then echo "BLOCKED: $v must be a numeric ID in Proxmox's accepted range." >&2; exit 2; fi; done
# Validate the desired guest IP network. Do not calculate/guess gateway, prefix or IDs.
python3 - "$WINDOWS_GUEST_IP" "$UBUNTU_GUEST_IP" "$SUBNET_PREFIX" "$GATEWAY" "$PVE01_IP" "$PVE02_IP" <<'PY'
import ipaddress,sys
w,u,p,g,n1,n2=sys.argv[1:]
try:
    prefix=int(p.lstrip('/'))
    net1=ipaddress.ip_network(f'{w}/{prefix}', strict=False)
    net2=ipaddress.ip_network(f'{u}/{prefix}', strict=False)
    gw=ipaddress.ip_address(g)
    ips=[ipaddress.ip_address(w),ipaddress.ip_address(u)]
    nodes=[ipaddress.ip_address(n1),ipaddress.ip_address(n2)]
    if not isinstance(gw,ipaddress.IPv4Address) or prefix<1 or prefix>30: raise ValueError('Use a verified IPv4 prefix between 1 and 30 for this lab.')
    if net1 != net2 or gw not in net1: raise ValueError('Guests and gateway must be in the same verified IPv4 subnet.')
    if ips[0] == ips[1] or any(x in nodes for x in ips): raise ValueError('Guest IPs must be unique and must not match Proxmox node IPs.')
    if any(x == net1.network_address or x == net1.broadcast_address for x in ips): raise ValueError('Guest IP cannot be subnet network/broadcast address.')
except Exception as e:
    print(f'BLOCKED: invalid guest network config: {e}',file=sys.stderr);sys.exit(2)
PY
[[ $? -eq 0 ]] || exit 2
# Check workbook/IP collisions. PROPOSED template rows are intentionally not treated as active conflicts.
python3 "$ROOT/scripts/inventory_check.py" --path "${INVENTORY_PATH:-inventory/environment-inventory.xlsx}" --worksheet Envir --target-ip "$WINDOWS_GUEST_IP" --target-ip "$UBUNTU_GUEST_IP"
inv_rc=$?
if [[ $inv_rc -ne 0 ]]; then echo 'BLOCKED: inventory source error or an active inventory conflict was found.' >&2; exit 2; fi
# Build report helper before live probes so their evidence is retained.
OUT_DIR="${REPORT_DIR:-$ROOT/reports/generated}"; mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"; RAW="$OUT_DIR/guest-deployment-$STAMP.jsonl"; PREFIX="$OUT_DIR/guest-deployment"
record() { python3 - "$RAW" "$1" "$2" "$3" "$4" "$5" <<'PY'
import json,sys,datetime
p,n,s,c,e,r=sys.argv[1:]
with open(p,'a',encoding='utf-8') as f:f.write(json.dumps({'name':n,'status':s,'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':c,'evidence':e,'remediation':r})+'\n')
PY
}
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=7)
record 'Guest IP external reservation attestation' PASS 'Operator confirmed router/DHCP reservations and workbook review' "Windows=$WINDOWS_GUEST_IP; Ubuntu=$UBUNTU_GUEST_IP; GUEST_IP_AVAILABILITY_CONFIRMED=YES" 'This is an operator assertion, not an automatic DHCP query. Keep reservation evidence in local records.'
# Fast conflict probes run on both Proxmox nodes. A failed ping alone never proves that an address is unused.
for ip in "$WINDOWS_GUEST_IP" "$UBUNTU_GUEST_IP"; do
  for node in "$PVE01_HOST" "$PVE02_HOST"; do
    if ! ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" 'command -v ping >/dev/null && command -v ip >/dev/null' >/dev/null 2>&1; then
      record "IP probe tools on $node" FAIL 'command -v ping && command -v ip' 'Remote probe tools or SSH unavailable.' 'Resolve SSH/tool access before deployment.'
      echo "BLOCKED: cannot run IP conflict probes from $node; verify tool/SSH availability first." >&2; exit 2
    fi
    if ping_out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" "ping -c 1 -W 1 '$ip'" 2>&1); then
      record "Guest IP $ip ping conflict probe from $node" FAIL "ping -c 1 -W 1 $ip" "$ping_out" 'An IP reply suggests a conflict. Investigate or select a different address.'
      echo "BLOCKED: $ip replied to ping from $node. Treat it as a conflict; choose another address after investigation." >&2; exit 2
    else
      record "Guest IP $ip ping conflict probe from $node" PASS "ping -c 1 -W 1 $ip" "$ping_out (no reply observed; this alone does not prove availability)" 'Use independent router/DHCP reservations and inventory evidence; do not infer that the address is unused from failed ping alone.'
    fi
    neigh=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" "ip neigh show to '$ip'" 2>&1) || { record "Guest IP $ip neighbour probe from $node" FAIL "ip neigh show to $ip" "$neigh" 'Resolve neighbour-table access before deployment.'; echo "BLOCKED: neighbour-table check failed from $node for $ip: $neigh" >&2; exit 2; }
    if printf '%s\n' "$neigh" | grep -Eq 'lladdr[[:space:]]+[0-9A-Fa-f:]{17}'; then
      record "Guest IP $ip neighbour probe from $node" FAIL "ip neigh show to $ip" "$neigh" 'A neighbor MAC suggests a conflict; investigate before using the address.'
      echo "BLOCKED: neighbour-table entry with a MAC address exists for $ip on $node: $neigh" >&2; exit 2
    else
      record "Guest IP $ip neighbour probe from $node" PASS "ip neigh show to $ip" "${neigh:-No neighbour entry returned}" 'No neighbor entry is not proof of availability; independent router/DHCP and inventory review remains required.'
    fi
  done
done
# Cluster/quorum and storage checks. A dry run requires the cluster to be healthy.
for pair in "$WINDOWS_NODE:$WINDOWS_VMID:$WINDOWS_GUEST_NAME:$WINDOWS_ISO:win" "$UBUNTU_NODE:$UBUNTU_VMID:$UBUNTU_GUEST_NAME:$UBUNTU_ISO:ubuntu"; do
  IFS=: read -r node vmid name iso os_type <<< "$pair"
  [[ "$node" == "$PVE01_HOST" || "$node" == "$PVE02_HOST" ]] || { echo "BLOCKED: node '$node' must be one of configured cluster nodes ($PVE01_HOST/$PVE02_HOST)." >&2; exit 2; }
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]] || { echo "BLOCKED: invalid guest name '$name'." >&2; exit 2; }
  [[ "$iso" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*\.iso$ ]] || { echo "BLOCKED: ISO values must be plain filenames with .iso extension already uploaded to Proxmox storage." >&2; exit 2; }
done
if [[ ! "${WINDOWS_OS_TYPE:-}" =~ ^(win10|win11|w2k22|w2k25)$ ]]; then echo 'BLOCKED: set WINDOWS_OS_TYPE to a supported explicit value: win10, win11, w2k22, or w2k25.' >&2; exit 2; fi
for node in "$PVE01_HOST" "$PVE02_HOST"; do
  if ! out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" 'pvecm status' 2>&1); then record "Cluster status $node" FAIL 'pvecm status' "$out" 'Cluster must be reachable and quorate.'; echo "BLOCKED: unable to query cluster status from $node." >&2; exit 2; fi
  if ! printf '%s' "$out" | grep -Eiq 'Quorate:[[:space:]]*Yes'; then record "Cluster quorum $node" FAIL 'pvecm status' "$out" 'Fix quorum; do not use pvecm expected 1 as a permanent fix.'; echo "BLOCKED: cluster on $node is not quorate." >&2; exit 2; fi
  record "Cluster quorum $node" PASS 'pvecm status' "$out" 'Two-node quorum can be lost if either node is unavailable; consider QDevice/third voter.'
done
if ! nodes_out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$PVE01_HOST" 'pvecm nodes' 2>&1); then echo 'BLOCKED: unable to query cluster membership.' >&2; exit 2; fi
for node in "$PVE01_HOST" "$PVE02_HOST"; do if ! printf '%s' "$nodes_out" | grep -Fq "$node"; then echo "BLOCKED: cluster membership output does not show $node." >&2; exit 2; fi; done
record 'Both nodes listed in cluster' PASS 'pvecm nodes' "$nodes_out" 'Verify actual online state in the Proxmox GUI/API as well.'

# Read cluster-wide VM and container inventories. A failed qm/pct command blocks; it is not treated as an unused ID.
for node in "$PVE01_HOST" "$PVE02_HOST"; do
  if ! inventory_out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" 'qm list && pct list' 2>&1); then
    record "VM/container inventory on $node" FAIL 'qm list && pct list' "$inventory_out" 'Resolve SSH or Proxmox inventory errors before deployment.'
    echo "BLOCKED: unable to confirm VM/container IDs on $node." >&2; exit 2
  fi
  for vmid in "$WINDOWS_VMID" "$UBUNTU_VMID"; do
    if printf '%s\n' "$inventory_out" | awk -v id="$vmid" '$1 == id { found=1 } END { exit !found }'; then
      record "VM ID $vmid unused" FAIL "qm list && pct list on $node" "$inventory_out" 'Choose an unused cluster-wide VM ID; nothing was deleted.'
      echo "BLOCKED: VM/container ID $vmid already appears in inventory on $node." >&2; exit 2
    else
      record "VM ID $vmid unused" PASS "qm list && pct list on $node" "ID $vmid was not present in the successful VM/container listings." 'Re-check just before creation; no deletion or automatic cleanup is performed.'
    fi
  done
done
if ! ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$WINDOWS_NODE" "pvesm list '$PVE_ISO_STORAGE' --content iso | grep -F -- '$WINDOWS_ISO' >/dev/null && pvesm status | grep -F '$PVE_STORAGE' >/dev/null" >/dev/null 2>&1; then echo "BLOCKED: disk/ISO storage '$PVE_STORAGE'/'$PVE_ISO_STORAGE' or Windows ISO is not ready on $WINDOWS_NODE." >&2; exit 2; fi
if ! ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$UBUNTU_NODE" "pvesm list '$PVE_ISO_STORAGE' --content iso | grep -F -- '$UBUNTU_ISO' >/dev/null && pvesm status | grep -F '$PVE_STORAGE' >/dev/null" >/dev/null 2>&1; then echo "BLOCKED: disk/ISO storage '$PVE_STORAGE'/'$PVE_ISO_STORAGE' or Ubuntu ISO is not ready on $UBUNTU_NODE." >&2; exit 2; fi

cat <<PLAN
Guest deployment plan (exactly two VMs; no changes made in dry-run):
  Windows: name=$WINDOWS_GUEST_NAME vmid=$WINDOWS_VMID node=$WINDOWS_NODE ip=$WINDOWS_GUEST_IP iso=$WINDOWS_ISO os=$WINDOWS_OS_TYPE
  Ubuntu:  name=$UBUNTU_GUEST_NAME vmid=$UBUNTU_VMID node=$UBUNTU_NODE ip=$UBUNTU_GUEST_IP iso=$UBUNTU_ISO
  disk_storage=$PVE_STORAGE iso_storage=$PVE_ISO_STORAGE bridge=$VM_BRIDGE subnet=/$SUBNET_PREFIX gateway=$GATEWAY
PLAN
if [[ $APPLY -ne 1 ]]; then
  record 'Guest creation gate' 'NOT RUN' 'No --apply flag by default' 'Plan shown; no VM created or started.' 'Review the VM IDs, ISO filenames, network values, storage capacity, and installer choices.'
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Windows and Ubuntu guest deployment (dry run)' || true
  exit 0
fi
if [[ $CONFIRM_FLAG -ne 1 ]]; then echo 'BLOCKED: --confirm-guest-deployment is also required with --apply.' >&2; exit 2; fi
printf "Type exactly 'DEPLOY GUESTS %s %s' to continue: " "$WINDOWS_VMID" "$UBUNTU_VMID"
IFS= read -r typed
if [[ "$typed" != "DEPLOY GUESTS $WINDOWS_VMID $UBUNTU_VMID" ]]; then echo 'Confirmation did not match; no VM creation attempted.' >&2; exit 2; fi

# Recheck names, VM IDs, cluster quorum, and ISO files just before the irreversible create calls.
for spec in "$WINDOWS_NODE|$WINDOWS_VMID|$WINDOWS_GUEST_NAME|$WINDOWS_ISO|$WINDOWS_OS_TYPE|$WINDOWS_DISK_GIB|$WINDOWS_RAM_MIB|$WINDOWS_VCPU" "$UBUNTU_NODE|$UBUNTU_VMID|$UBUNTU_GUEST_NAME|$UBUNTU_ISO|l26|$UBUNTU_DISK_GIB|$UBUNTU_RAM_MIB|$UBUNTU_VCPU"; do
  IFS='|' read -r node vmid name iso ostype disk ram vcpu <<< "$spec"
  if ! ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" "test -e /etc/pve/corosync.conf && pvecm status | grep -Eiq 'Quorate:[[:space:]]*Yes' && ! qm config '$vmid' >/dev/null 2>&1 && pvesm status | grep -F '$PVE_STORAGE' >/dev/null && pvesm list '$PVE_ISO_STORAGE' --content iso | grep -F -- '$iso' >/dev/null"; then
    echo "BLOCKED: final safety re-check failed on $node for VM ID $vmid, storage, ISO, or quorum." >&2; exit 2
  fi
done

create_vm() {
  local node="$1" vmid="$2" name="$3" iso="$4" ostype="$5" disk="$6" ram="$7" cpu="$8" args
  local base="qm create $vmid --name $name --ostype $ostype --memory $ram --cores $cpu --cpu host --scsihw virtio-scsi-single --net0 virtio,bridge=$VM_BRIDGE --scsi0 $PVE_STORAGE:$disk --ide2 $PVE_ISO_STORAGE:iso/$iso,media=cdrom --boot order=ide2\\;scsi0 --onboot 0"
  if [[ "$ostype" == win11 ]]; then
    base="$base --machine q35 --bios ovmf --efidisk0 $PVE_STORAGE:1,efitype=4m,pre-enrolled-keys=1 --tpmstate0 $PVE_STORAGE:1,version=v2.0"
  fi
  if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" "$base" 2>&1); then record "Create $name ($vmid)" PASS "$base" "$out" 'The guest installer is interactive; verify firmware/TPM, VirtIO drivers, and guest networking during installation.'
  else rc=$?; record "Create $name ($vmid)" FAIL "$base" "$out (exit $rc)" 'Stop and inspect the partial VM state; never delete automatically.'; return 1; fi
}
if ! create_vm "$WINDOWS_NODE" "$WINDOWS_VMID" "$WINDOWS_GUEST_NAME" "$WINDOWS_ISO" "$WINDOWS_OS_TYPE" "$WINDOWS_DISK_GIB" "$WINDOWS_RAM_MIB" "$WINDOWS_VCPU"; then python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Windows and Ubuntu guest deployment' || true; exit 2; fi
if ! create_vm "$UBUNTU_NODE" "$UBUNTU_VMID" "$UBUNTU_GUEST_NAME" "$UBUNTU_ISO" 'l26' "$UBUNTU_DISK_GIB" "$UBUNTU_RAM_MIB" "$UBUNTU_VCPU"; then python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Windows and Ubuntu guest deployment' || true; exit 2; fi
for pair in "$WINDOWS_NODE:$WINDOWS_VMID:$WINDOWS_GUEST_NAME" "$UBUNTU_NODE:$UBUNTU_VMID:$UBUNTU_GUEST_NAME"; do IFS=: read -r node id name <<< "$pair"; if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$node" "qm start '$id'" 2>&1); then record "Start $name ($id)" PASS "qm start $id" "$out" 'Complete OS installation interactively using official media.'; else rc=$?; record "Start $name ($id)" FAIL "qm start $id" "$out (exit $rc)" 'Inspect VM hardware/storage and start it manually after diagnosing.'; fi; done
python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Windows and Ubuntu guest deployment'
