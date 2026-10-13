#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPORT_DIR:-$ROOT/reports/generated}"
mkdir -p "$OUT_DIR"
PVE01_HOST="${PVE01_HOST:-pve01}"; PVE02_HOST="${PVE02_HOST:-pve02}"
PVE01_IP="${PVE01_IP:-192.168.1.111}"; PVE02_IP="${PVE02_IP:-192.168.1.112}"
PVE_SSH_USER="${PVE_SSH_USER:-root}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
APPLY=0; CONFIRM_FLAG=0
for arg in "$@"; do case "$arg" in
  --apply) APPLY=1;;
  --confirm-cluster-creation) CONFIRM_FLAG=1;;
  --help|-h) echo 'Usage: configure-cluster.sh [--apply --confirm-cluster-creation]'; echo 'No flags = preflight only. Cluster formation is destructive/irreversible in practice and requires typed confirmation.'; exit 0;;
  *) echo "Unknown argument: $arg" >&2; exit 64;;
esac; done
if [[ -z "$CLUSTER_NAME" || ! "$CLUSTER_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,14}$ ]]; then
  echo 'BLOCKED: Set CLUSTER_NAME to a verified unique cluster name (1-15 alphanumeric/dot/hyphen characters).' >&2; exit 2
fi
if [[ "$PVE01_IP" == "$PVE02_IP" ]]; then echo 'BLOCKED: node IP addresses must differ.' >&2; exit 2; fi
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=7)
RAW="$OUT_DIR/cluster-status-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
PREFIX="$OUT_DIR/cluster-status"
record() { python3 - "$RAW" "$1" "$2" "$3" "$4" "$5" <<'PY'
import json,sys,datetime
p,n,s,c,e,r=sys.argv[1:]
with open(p,'a',encoding='utf-8') as f:f.write(json.dumps({'name':n,'status':s,'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':c,'evidence':e,'remediation':r})+'\n')
PY
}
run() { local desc="$1" host="$2" command="$3" rem="$4" out rc; if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$host" "$command" 2>&1); then rc=0; else rc=$?; fi; if [[ $rc -eq 0 ]]; then record "$desc" PASS "ssh $PVE_SSH_USER@$host $command" "${out:-success}" "$rem"; else record "$desc" FAIL "ssh $PVE_SSH_USER@$host $command" "$out (exit $rc)" "$rem"; fi; return "$rc"; }
: > "$RAW"
echo 'Cluster preflight: inspecting nodes; no cluster changes have been made.'
set +e
"$ROOT/scripts/check-proxmox-nodes.sh"
node_rc=$?
set -e
if [[ $node_rc -ne 0 ]]; then
  record 'Cluster creation gate' BLOCKED 'check-proxmox-nodes.sh' 'At least one required readiness check did not pass.' 'Resolve failures and manually verify Corosync network policy, then rerun preflight.'
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox cluster formation status' || true
  echo 'BLOCKED: readiness checks must all pass before cluster creation.' >&2
  exit 2
fi
# Repeat critical no-existing-cluster and no-workload checks immediately before the action.
run 'pve01 no pre-existing cluster config' "$PVE01_HOST" 'test ! -e /etc/pve/corosync.conf' 'Stop if this node is already clustered.' || node_rc=2
run 'pve02 no pre-existing cluster config' "$PVE02_HOST" 'test ! -e /etc/pve/corosync.conf' 'Stop if this node is already clustered.' || node_rc=2
check_empty_workloads() {
  local host="$1" kind out ids
  for kind in qm pct; do
    if ! out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$host" "$kind list" 2>&1); then
      record "$host $kind workload inventory" FAIL "ssh $host $kind list" "$out" 'Resolve inventory access before cluster formation.'
      return 1
    fi
    ids=$(printf '%s\n' "$out" | awk 'NR > 1 && $1 ~ /^[0-9]+$/ { print $1 }')
    if [[ -n "$ids" ]]; then
      record "$host $kind workload inventory" BLOCKED "ssh $host $kind list" "$out" 'This new lab requires empty Proxmox nodes. Back up/migrate workloads and make a separate approved plan; this script will not delete or overwrite them.'
      echo "BLOCKED: existing $kind workload(s) on $host: $ids. No cluster changes attempted." >&2
      return 1
    fi
    record "$host $kind workload inventory" PASS "ssh $host $kind list" "$out" 'No existing guest workloads detected.'
  done
}
check_empty_workloads "$PVE01_HOST" || node_rc=2
check_empty_workloads "$PVE02_HOST" || node_rc=2
if [[ $node_rc -ne 0 ]]; then
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox cluster formation status' || true
  echo 'BLOCKED: a cluster or inventory check failed. No cluster changes attempted.' >&2; exit 2
fi
if [[ $APPLY -ne 1 ]]; then
  record 'Cluster formation approval' 'NOT RUN' 'No --apply flag by default' "Planned: cluster '$CLUSTER_NAME'; pve01=$PVE01_IP; pve02=$PVE02_IP" 'Review all evidence and the node/VM inventory. Confirm the exact node pair and unique cluster name.'
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox cluster readiness (dry run)' || true
  echo 'Dry-run complete. No cluster was created. Re-run with --apply --confirm-cluster-creation only after review.'
  exit 0
fi
if [[ $CONFIRM_FLAG -ne 1 ]]; then echo 'BLOCKED: --confirm-cluster-creation is also required with --apply.' >&2; exit 2; fi
record 'Cluster formation approval' PASS 'Explicit --apply --confirm-cluster-creation flags' "Planned cluster '$CLUSTER_NAME'; pve01=$PVE01_IP; pve02=$PVE02_IP" 'Typed confirmation is still required.'
printf "Type exactly 'CREATE CLUSTER %s' to continue: " "$CLUSTER_NAME"
IFS= read -r typed
if [[ "$typed" != "CREATE CLUSTER $CLUSTER_NAME" ]]; then echo 'Confirmation did not match; no cluster changes made.' >&2; exit 2; fi
if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$PVE01_HOST" "pvecm create '$CLUSTER_NAME' --link0 '$PVE01_IP'" 2>&1); then
  record 'Create cluster on pve01' PASS "pvecm create $CLUSTER_NAME --link0 $PVE01_IP" "$out" 'If cluster creation fails, inspect the Proxmox journal and official guide before retrying.'
else
  rc=$?; record 'Create cluster on pve01' FAIL "pvecm create $CLUSTER_NAME --link0 $PVE01_IP" "$out (exit $rc)" 'Stop immediately; do not run reset/destroy commands automatically.'
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox cluster formation status' || true; exit 2
fi
if out=$(ssh -tt "$PVE_SSH_USER@$PVE02_HOST" "pvecm add '$PVE01_IP' --link0 '$PVE02_IP'" 2>&1); then
  record 'Join pve02 to cluster' PASS "pvecm add $PVE01_IP --link0 $PVE02_IP" "$out" 'Keep the two-node quorum limitation in mind.'
else
  rc=$?; record 'Join pve02 to cluster' FAIL "pvecm add $PVE01_IP --link0 $PVE02_IP" "$out (exit $rc)" 'Cluster may be created on pve01 but join failed. Stop and diagnose; do not retry destructive operations.'
  python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox cluster formation status' || true; exit 2
fi
for host in "$PVE01_HOST" "$PVE02_HOST"; do
  if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$host" 'pvecm status' 2>&1); then
    if printf '%s' "$out" | grep -Eiq 'Quorate:[[:space:]]*Yes'; then record "Quorum on $host" PASS "ssh $host pvecm status" "$out" 'Both nodes must remain online for a basic two-vote quorum.'
    else record "Quorum on $host" FAIL "ssh $host pvecm status" "$out" 'Investigate corosync/quorum; do not use pvecm expected 1 as a permanent fix.'; fi
  else record "Quorum on $host" FAIL "ssh $host pvecm status" "$out" 'Inspect cluster networking and Corosync logs.'; fi
done
if out=$(ssh "${SSH_OPTS[@]}" "$PVE_SSH_USER@$PVE01_HOST" 'pvecm nodes' 2>&1); then
  if printf '%s' "$out" | grep -Fq "$PVE01_HOST" && printf '%s' "$out" | grep -Fq "$PVE02_HOST"; then record 'Cluster membership' PASS 'pvecm nodes' "$out" 'Confirm both nodes are online, not merely listed.'
  else record 'Cluster membership' FAIL 'pvecm nodes' "$out" 'Both intended nodes must be present.'; fi
else record 'Cluster membership' FAIL 'pvecm nodes' "$out" 'Inspect cluster status.'; fi
python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Proxmox cluster formation status'
