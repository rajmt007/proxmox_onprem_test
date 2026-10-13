[CmdletBinding()]
param(
    [string[]]$TargetIP = @('192.168.1.111','192.168.1.112'),
    [string]$ReportDirectory = 'reports/generated'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null
$rows = foreach ($ip in $TargetIP) {
    $responded = $false; $pingEvidence = 'No reply'; $neighbor = $null
    try {
        $reply = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
        $responded = [bool]$reply
        if ($responded) { $pingEvidence = 'Echo reply received' }
    } catch { $pingEvidence = $_.Exception.Message }
    try { $neighbor = Get-NetNeighbor -AddressFamily IPv4 -IPAddress $ip -ErrorAction SilentlyContinue | Select-Object -First 1 } catch {}
    $macFound = $neighbor -and $neighbor.LinkLayerAddress -and $neighbor.LinkLayerAddress -notmatch '^00-00-00-00-00-00$'
    if ($responded -or $macFound) { $status = 'CONFLICT' }
    else { $status = 'UNKNOWN_BLOCKED' }
    [pscustomobject]@{
        target_ip=$ip; status=$status; timestamp_utc=(Get-Date).ToUniversalTime().ToString('o')
        ping_reply=$responded; ping_evidence=$pingEvidence
        neighbor_state=$(if ($neighbor) {$neighbor.State} else {'NO_NEIGHBOR_ENTRY'})
        neighbor_mac=$(if ($neighbor) {$neighbor.LinkLayerAddress} else {''})
        authoritative_dhcp_router_checked=$false
        note='A failed ping and an empty neighbor cache do not prove an address is unused. Check DHCP/router reservations separately.'
    }
}
$stamp = Get-Date -Format 'yyyyMMddTHHmmssZ'
$json = Join-Path $ReportDirectory "ip-conflicts-$stamp.json"
$csv = Join-Path $ReportDirectory "ip-conflicts-$stamp.csv"
$rows | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $json
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $csv
$rows | Format-Table target_ip,status,ping_reply,neighbor_state,neighbor_mac -AutoSize
Write-Host "JSON: $json`nCSV: $csv"
if (@($rows | Where-Object status -ne 'PASS').Count -gt 0) { exit 2 }
