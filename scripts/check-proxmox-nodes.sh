#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPORT_DIR:-$ROOT/reports/generated}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RAW="$OUT_DIR/proxmox-preflight-$STAMP.jsonl"
PREFIX="$OUT_DIR/proxmox-preflight"
PVE01_HOST="${PVE01_HOST:-pve01}"; PVE02_HOST="${PVE02_HOST:-pve02}"
PVE01_IP="${PVE01_IP:-192.168.1.111}"; PVE02_IP="${PVE02_IP:-192.168.1.112}"
PVE_SSH_USER="${PVE_SSH_USER:-root}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=7)

record() {
  local name="$1" status="$2" command="$3" evidence="$4" remediation="${5:-}"
  python3 - "$RAW" "$name" "$status" "$command" "$evidence" "$remediation" <<'PY'
import json,sys,datetime
path,name,status,command,evidence,remediation=sys.argv[1:]
obj={"name":name,"status":status,"timestamp_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"command":command,"evidence":evidence,"remediation":remediation}
with open(path,"a",encoding="utf-8") as f: f.write(json.dumps(obj,ensure_ascii=False)+"\n")
PY
}
run_check() {
  local name="$1" target="$2" remote_command="$3" remediation="$4" out rc
  if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$target" "$remote_command" 2>&1); then rc=0; else rc=$?; fi
  if [[ $rc -eq 0 ]]; then record "$name" PASS "ssh $PVE_SSH_USER@$target $remote_command" "${out:-command completed with no output}" "$remediation"
  else record "$name" FAIL "ssh $PVE_SSH_USER@$target $remote_command" "$out (exit $rc)" "$remediation"; fi
  return "$rc"
}
: > "$RAW"
if ! command -v ssh >/dev/null; then
  record 'SSH client available' FAIL 'command -v ssh' 'ssh executable not found' 'Install an OpenSSH client.'
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox node readiness preflight' || true
  exit 2
fi

run_check 'SSH reachability pve01' "$PVE01_HOST" 'printf reachable' 'Check routing, SSH service, known_hosts, and key-based authentication.' || true
run_check 'SSH reachability pve02' "$PVE02_HOST" 'printf reachable' 'Check routing, SSH service, known_hosts, and key-based authentication.' || true
run_check 'Proxmox version pve01' "$PVE01_HOST" 'pveversion' 'Install Proxmox VE on a dedicated VM; an attached ISO is not an installed node.' || true
run_check 'Proxmox version pve02' "$PVE02_HOST" 'pveversion' 'Install compatible Proxmox VE versions on both nodes.' || true
# Compare major/minor version numbers only after both commands return version text.
v1=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$PVE01_HOST" 'pveversion' 2>/dev/null || true)
v2=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$PVE02_HOST" 'pveversion' 2>/dev/null || true)
version1=$(printf '%s' "$v1" | sed -n 's#.*pve-manager/\([0-9][0-9]*\.[0-9][0-9]*\).*#\1#p' | head -1)
version2=$(printf '%s' "$v2" | sed -n 's#.*pve-manager/\([0-9][0-9]*\.[0-9][0-9]*\).*#\1#p' | head -1)
if [[ -n "$version1" && "$version1" == "$version2" ]]; then record 'Version compatibility' PASS 'pveversion on both nodes' "pve01=$version1; pve02=$version2" 'Use compatible supported Proxmox VE versions.'
else record 'Version compatibility' FAIL 'pveversion on both nodes' "pve01=${version1:-unknown}; pve02=${version2:-unknown}" 'Install/upgrade to compatible versions before creating a cluster.'; fi

run_check 'pve01 configured target IP' "$PVE01_HOST" "ip -o -4 addr show | grep -F '$PVE01_IP/'" 'Configure the requested address on the intended management interface and bridge.' || true
run_check 'pve02 configured target IP' "$PVE02_HOST" "ip -o -4 addr show | grep -F '$PVE02_IP/'" 'Configure the requested address on the intended management interface and bridge.' || true
run_check 'pve01 reaches pve02' "$PVE01_HOST" "ping -c 1 -W 2 '$PVE02_IP'" 'Check bridged network, routing, VLAN, and narrowly scoped ICMP/firewall rules.' || true
run_check 'pve02 reaches pve01' "$PVE02_HOST" "ping -c 1 -W 2 '$PVE01_IP'" 'Check bridged network, routing, VLAN, and narrowly scoped ICMP/firewall rules.' || true
run_check 'pve01 hostname resolution for pve02' "$PVE01_HOST" "getent hosts '$PVE02_HOST'" 'Ensure both hostnames resolve to the correct stable addresses from both nodes.' || true
run_check 'pve02 hostname resolution for pve01' "$PVE02_HOST" "getent hosts '$PVE01_HOST'" 'Ensure both hostnames resolve to the correct stable addresses from both nodes.' || true
run_check 'pve01 time synchronization' "$PVE01_HOST" "timedatectl show -p NTPSynchronized --value | grep -Ei '^(yes|true)$'" 'Configure working NTP/time synchronization.' || true
run_check 'pve02 time synchronization' "$PVE02_HOST" "timedatectl show -p NTPSynchronized --value | grep -Ei '^(yes|true)$'" 'Configure working NTP/time synchronization.' || true
run_check 'pve01 nested KVM available' "$PVE01_HOST" 'test -e /dev/kvm && test -r /dev/kvm' 'Enable VMware nested virtualization and ensure host/BIOS virtualization support is exposed.' || true
run_check 'pve02 nested KVM available' "$PVE02_HOST" 'test -e /dev/kvm && test -r /dev/kvm' 'Enable VMware nested virtualization and ensure host/BIOS virtualization support is exposed.' || true
run_check 'pve01 not in an existing cluster' "$PVE01_HOST" 'test ! -e /etc/pve/corosync.conf' 'Do not overwrite or join an unrelated existing cluster.' || true
run_check 'pve02 not in an existing cluster' "$PVE02_HOST" 'test ! -e /etc/pve/corosync.conf' 'Do not overwrite or join an unrelated existing cluster.' || true
run_check 'pve01 storage status' "$PVE01_HOST" 'pvesm status' 'Confirm intended storage is online and has safe free capacity.' || true
run_check 'pve02 storage status' "$PVE02_HOST" 'pvesm status' 'Confirm intended storage is online and has safe free capacity.' || true
if [[ "${COROSYNC_NETWORK_CONFIRMED:-NO}" == 'YES' ]]; then
  record 'Corosync network reviewed' PASS 'Manual confirmation: COROSYNC_NETWORK_CONFIRMED=YES' 'Operator confirmed the selected low-latency link and required network/firewall reachability.' 'Use a dedicated reliable network where possible; ping alone does not prove all Corosync traffic is allowed.'
else
  record 'Corosync network reviewed' NOT_RUN 'Manual network/firewall review required' 'Not confirmed. UDP traffic/port policy and selected link have not been validated.' 'Review official Proxmox cluster networking requirements, firewall/VLAN paths and stability, then set COROSYNC_NETWORK_CONFIRMED=YES after actually checking.'
fi
python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox node readiness preflight'
