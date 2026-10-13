#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPORT_DIR:-$ROOT/reports/generated}"; mkdir -p "$OUT_DIR"
RAW="$OUT_DIR/guest-connectivity-$(date -u +%Y%m%dT%H%M%SZ).jsonl"; PREFIX="$OUT_DIR/guest-connectivity"
record() { python3 - "$RAW" "$1" "$2" "$3" "$4" "$5" <<'PY'
import json,sys,datetime
p,n,s,c,e,r=sys.argv[1:]
with open(p,'a',encoding='utf-8') as f:f.write(json.dumps({'name':n,'status':s,'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command':c,'evidence':e,'remediation':r})+'\n')
PY
}
if [[ -z "${WINDOWS_GUEST_IP:-}" || -z "${UBUNTU_GUEST_IP:-}" ]]; then echo 'BLOCKED: set WINDOWS_GUEST_IP and UBUNTU_GUEST_IP from verified guest configuration.' >&2; exit 2; fi
if [[ "$WINDOWS_GUEST_IP" == "$UBUNTU_GUEST_IP" ]]; then echo 'BLOCKED: guest IPs must differ.' >&2; exit 2; fi
: > "$RAW"
probe() {
  local label="$1" target="$2" ip="$3" cmd="$4" out rc
  if [[ -z "$target" ]]; then record "$label" 'NOT RUN' "$cmd" 'Target SSH endpoint is not configured.' 'Configure key-based SSH to the guest. On Windows, enable OpenSSH Server or run the PowerShell probe locally.'; return; fi
  if out=$(ssh -o BatchMode=yes -o ConnectTimeout=7 "$target" "$cmd" 2>&1); then rc=0; else rc=$?; fi
  if [[ $rc -eq 0 ]]; then
    if printf '%s' "$out" | grep -Eiq '100% packet loss|100% loss|Destination Host Unreachable|Network is unreachable|Received[[:space:]]*=[[:space:]]*0|0 received|Lost[[:space:]]*=[[:space:]]*4'; then status=FAIL
    else status=PASS; fi
    record "$label" "$status" "ssh $target $cmd" "$out" 'No echo replies are a failed probe, not proof of a firewall cause. Check routing, guest power, VLAN and narrow firewall rules; if ICMP is intentionally blocked, test an approved TCP service.'
  else record "$label" 'NOT RUN' "ssh $target $cmd" "$out (exit $rc)" 'Guest SSH/credentials/firewall did not permit an in-guest test; do not infer network failure from SSH failure.'; fi
}
# Commands execute on the remote guest, not just the controller.
probe 'Ubuntu to Windows ICMP' "${UBUNTU_SSH_TARGET:-}" "$WINDOWS_GUEST_IP" "ping -c 4 -W 2 '$WINDOWS_GUEST_IP' || true"
probe 'Windows to Ubuntu ICMP' "${WINDOWS_SSH_TARGET:-}" "$UBUNTU_GUEST_IP" "ping -n 4 -w 2000 '$UBUNTU_GUEST_IP' || true"
python3 "$ROOT/scripts/finalize_report.py" --input "$RAW" --prefix "$PREFIX" --title 'Guest-to-guest connectivity' || true
printf 'Reports: %s.md, %s.json, %s.csv\n' "$PREFIX" "$PREFIX" "$PREFIX"
# NOT RUN is not a pass; return nonzero unless both directional tests passed.
python3 - "$RAW" <<'PY'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1],encoding='utf-8') if x.strip()]
sys.exit(0 if len(rows)==2 and all(x['status']=='PASS' for x in rows) else 2)
PY
