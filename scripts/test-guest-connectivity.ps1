[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UbuntuGuestIP,
    [string]$ReportDirectory = 'reports/generated'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$time = (Get-Date).ToUniversalTime().ToString('o')
$rows = @()
try {
    $ping = Test-Connection -ComputerName $UbuntuGuestIP -Count 4 -ErrorAction Stop
    $received = @($ping).Count
    $loss = [math]::Round((4 - [math]::Min(4,$received)) / 4 * 100, 2)
    $rows += [pscustomobject]@{ name='Windows to Ubuntu ICMP'; status=$(if ($received -gt 0) {'PASS'} else {'FAIL'}); timestamp_utc=$time; source=$env:COMPUTERNAME; destination=$UbuntuGuestIP; method='Test-Connection (ICMP Echo)'; sent=4; received=$received; loss_percent=$loss; latency_ms=(@($ping | ForEach-Object { $_.ResponseTime }) -join ','); evidence="Received $received response(s)"; remediation='If blocked, check narrow ICMP rule and retest; do not disable the firewall globally.' }
} catch {
    $rows += [pscustomobject]@{ name='Windows to Ubuntu ICMP'; status='BLOCKED_BY_FIREWALL'; timestamp_utc=$time; source=$env:COMPUTERNAME; destination=$UbuntuGuestIP; method='Test-Connection (ICMP Echo)'; sent=4; received=0; loss_percent=100; latency_ms=''; evidence=$_.Exception.Message; remediation='ICMP may be blocked by Windows/Linux firewall or routing. Test an approved TCP service or add a narrowly scoped Echo rule only with approval.' }
}
$stamp = Get-Date -Format 'yyyyMMddTHHmmssZ'
$json = Join-Path $ReportDirectory 'guest-connectivity-windows-direction.json'
$csv = Join-Path $ReportDirectory "guest-connectivity-windows-direction-$stamp.csv"
$rows | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $json
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $csv
$rows | Format-Table name,status,source,destination,method,received,loss_percent -AutoSize
Write-Host "JSON: $json`nCSV: $csv"
if ($rows[0].status -ne 'PASS') { exit 2 }
