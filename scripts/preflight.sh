#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPORT_DIR:-$ROOT/reports/generated}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/host-preflight-$(date -u +%Y%m%dT%H%M%SZ).md"
STATUS=0
{
  echo '# Host preflight (Linux management/host machine)'
  echo "- Timestamp UTC: $(date -u +%FT%TZ)"
  echo "- Host: $(hostname -f 2>/dev/null || hostname)"
  echo
  check() {
    local name="$1" status="$2" evidence="$3" remediation="${4:-}"
    printf '## %s — %s\n\n- Evidence: `%s`\n' "$name" "$status" "${evidence//\`/\\\`}"
    [[ -n "$remediation" ]] && printf -- '- Remediation: %s\n' "$remediation"
    echo
    [[ "$status" == PASS ]] || STATUS=2
  }
  if command -v vmware >/dev/null 2>&1 || command -v vmplayer >/dev/null 2>&1 || command -v vmrun >/dev/null 2>&1; then
    check 'VMware CLI' PASS "$(command -v vmware || command -v vmplayer || command -v vmrun)"
  else
    check 'VMware CLI' 'NOT RUN' 'No VMware executable found in PATH' 'On a Windows Workstation host use scripts/preflight.ps1; Player editions may not expose the same CLI.'
  fi
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0)
  check 'CPU cores' "$([[ "$cores" -ge 8 ]] && echo PASS || echo FAIL)" "$cores online core(s)" 'Check actual workload capacity; example lab sizing totals 8 vCPUs before guest VMs.'
  if [[ -r /proc/meminfo ]]; then
    mem_kib=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_gib=$(awk -v m="$mem_kib" 'BEGIN {printf "%.2f", m/1024/1024}')
    check 'RAM' "$(awk -v m="$mem_kib" 'BEGIN {print (m>=20*1024*1024)?"PASS":"FAIL"}')" "${mem_gib} GiB total" 'Adjust the example allocations to fit actual host capacity.'
  else
    check 'RAM' 'NOT RUN' '/proc/meminfo unavailable' 'Run platform-appropriate host preflight.'
  fi
  free_gib=$(df -Pk "$ROOT" | awk 'NR==2 {printf "%.2f", $4/1024/1024}')
  check 'Free disk' "$(awk -v d="$free_gib" 'BEGIN {print (d>=150)?"PASS":"FAIL"}')" "${free_gib} GiB free on repository filesystem" 'Also check the specific VMware VM datastore filesystem.'
  if [[ -r /dev/kvm ]]; then check '/dev/kvm present on current host' PASS '/dev/kvm exists' 'This is a nested lab: also enable and verify nested virtualization within each VMware VM.'
  else check '/dev/kvm present on current host' 'NOT RUN' '/dev/kvm not present (not necessarily the physical Windows host)' 'Run the preflight on the actual VMware host and confirm VT-x/AMD-V can be exposed to guests.'; fi
  check 'Nested virtualization per VM' 'NOT RUN' 'VMware UI setting is not reliably queryable from this script' 'Enable Virtualize Intel VT-x/EPT or AMD-V/RVI in each VM Processor setting.'
  check 'IP reservation state' 'NOT RUN' 'Router/DHCP state is not available to this script' 'Confirm both requested IPs in the authoritative router/DHCP system; failed ping alone does not prove availability.'
} > "$REPORT"
cat "$REPORT"
exit "$STATUS"
