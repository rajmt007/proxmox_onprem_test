[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('pve01','pve02')][string]$VMName,
    [Parameter(Mandatory=$true)][string]$VMFolder,
    [Parameter(Mandatory=$true)][ValidateSet('192.168.1.111','192.168.1.112')][string]$TargetIP,
    [string]$ReportDirectory = 'reports/generated',
    [switch]$ConfirmTargetIpAvailability
)
$ErrorActionPreference = 'Stop'
$expectedIP = if ($VMName -eq 'pve01') { '192.168.1.111' } else { '192.168.1.112' }
if ($TargetIP -ne $expectedIP) { Write-Error "BLOCKED: $VMName is mapped to requested target $expectedIP; no address changes are permitted by this approval helper."; exit 2 }
$folder = [System.IO.Path]::GetFullPath($VMFolder)
$vmx = Join-Path $folder "$VMName.vmx"
if (-not (Test-Path -LiteralPath $vmx -PathType Leaf)) { Write-Error "BLOCKED: VMX file not found: $vmx"; exit 2 }
$contents = Get-Content -Raw -LiteralPath $vmx
$diskMatch = [regex]::Match($contents, '(?m)^scsi0:0\.fileName\s*=\s*"(?<value>[^"]+)"')
$isoMatch  = [regex]::Match($contents, '(?m)^ide1:0\.fileName\s*=\s*"(?<value>[^"]+)"')
if (-not $diskMatch.Success -or -not $isoMatch.Success) { Write-Error 'BLOCKED: expected disk and ISO entries were not found in the VMX file.'; exit 2 }
$diskValue = $diskMatch.Groups['value'].Value
$diskPath = if ([System.IO.Path]::IsPathRooted($diskValue)) { [System.IO.Path]::GetFullPath($diskValue) } else { [System.IO.Path]::GetFullPath((Join-Path $folder $diskValue)) }
$isoPath = $isoMatch.Groups['value'].Value.Replace('\\','\')
if (-not (Test-Path -LiteralPath $diskPath -PathType Leaf)) { Write-Error "BLOCKED: dedicated virtual disk not found: $diskPath"; exit 2 }
if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) { Write-Error "BLOCKED: installer ISO not found: $isoPath"; exit 2 }
$folderBoundary = $folder.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $diskPath.StartsWith($folderBoundary, [System.StringComparison]::OrdinalIgnoreCase)) { Write-Error 'BLOCKED: the selected virtual disk is outside the specified VM folder; preserving it.'; exit 2 }
$diskSectors = $null
try {
    $header = Get-Content -LiteralPath $diskPath -TotalCount 80 -ErrorAction Stop
    $sectorLine = $header | Where-Object { $_ -match '^RW\s+(\d+)\s+' } | Select-Object -First 1
    if ($sectorLine -match '^RW\s+(\d+)\s+') { $diskSectors = [double]$Matches[1] }
} catch {}
$virtualSizeGiB = if ($diskSectors) { [math]::Round(($diskSectors * 512) / [math]::Pow(1024,3), 2) } else { 'unknown (descriptor not readable)' }
$root = Split-Path -Parent $PSScriptRoot
$reportRoot = Join-Path $root $ReportDirectory
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$inventoryResult = & python (Join-Path $PSScriptRoot 'inventory_check.py') --path 'inventory/environment-inventory.xlsx' --worksheet Envir --target-ip $TargetIP --repo-root $root 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "BLOCKED: inventory scan failed or an active inventory match exists. $inventoryResult"; exit 2 }
$inventoryData = ($inventoryResult | Out-String) | ConvertFrom-Json
$matches = @($inventoryData.target_matches.$TargetIP)
Write-Host ''
Write-Host 'PROXMOX INSTALLATION SAFETY REVIEW — no installation is started by this script.'
Write-Host "VM name:             $VMName"
Write-Host "VMX file:            $vmx"
Write-Host "Selected disk path:  $diskPath"
Write-Host "Selected disk size:  $virtualSizeGiB GiB (virtual size; sparse physical allocation may be smaller)"
Write-Host "Installer ISO:       $isoPath"
Write-Host "Requested target IP: $TargetIP"
Write-Host 'Inventory matches:'
if ($matches.Count -eq 0) { Write-Host '  None in the current Envir inventory (this is not proof the address is available on the LAN).' }
else { $matches | ConvertTo-Json -Depth 5 | Write-Host; Write-Error 'BLOCKED: target IP matches inventory; resolve conflict before installation.'; exit 2 }
Write-Host 'Network evidence: check-ip-conflicts.ps1 reports conflict or unknown; router/DHCP reservations must be reviewed independently.'
if (-not $ConfirmTargetIpAvailability) { Write-Error 'BLOCKED: verify IP reservation/availability in router/DHCP, then re-run with -ConfirmTargetIpAvailability.'; exit 2 }
$ipScript = Join-Path $PSScriptRoot 'check-ip-conflicts.ps1'
$engine = (Get-Process -Id $PID).Path
$ipOutput = & $engine -NoProfile -ExecutionPolicy Bypass -File $ipScript -TargetIP $TargetIP -ReportDirectory $reportRoot 2>&1
$latest = Get-ChildItem -Path $reportRoot -Filter 'ip-conflicts-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    $networkState = Get-Content -Raw -LiteralPath $latest.FullName | ConvertFrom-Json | Where-Object target_ip -eq $TargetIP | Select-Object -First 1
    if ($networkState.status -eq 'CONFLICT') { Write-Error 'BLOCKED: live ping or neighbor evidence indicates a possible IP conflict.'; exit 2 }
}
$phrase = "INSTALL PROXMOX $VMName $TargetIP"
$typed = Read-Host "Confirm the selected disk will be erased by Proxmox installation. Type exactly '$phrase' after reviewing the displayed disk, size, ISO, IP, and inventory evidence"
if ($typed -cne $phrase) { Write-Error 'Confirmation did not match; no install approval produced.'; exit 2 }
$approval = [pscustomobject]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    approval_status = 'OPERATOR_CONFIRMED_FOR_MANUAL_INSTALL'
    vm_name = $VMName; vmx_path = $vmx; virtual_disk_path = $diskPath
    virtual_disk_size_gib = $virtualSizeGiB; iso_path = $isoPath; target_ip = $TargetIP
    inventory_match_count = $matches.Count
    lan_ip_availability = if ($networkState) { $networkState.status } else { 'UNKNOWN_BLOCKED' }
    router_dhcp_reservation_checked_by_operator = $true
    destructive_scope = 'Only the dedicated virtual disk path shown above; manually confirm selected disk in Proxmox installer UI.'
    note = 'This approval record does not install Proxmox or prove the target IP is free. Verify the VM disk selection in the installer before confirming disk wipe.'
}
$outFile = Join-Path $reportRoot "proxmox-install-approval-$VMName.json"
$approval | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $outFile
Write-Host "Approval record written: $outFile"
Write-Host 'Now review the exact target disk in the VMware console before confirming the Proxmox installation. No installation was started automatically.'
