[CmdletBinding()]
param(
    [string]$ReportPath = "reports/generated/host-preflight.json"
)
$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check([string]$Name, [string]$Status, [string]$Command, [string]$Evidence, [string]$Remediation = '') {
    $checks.Add([pscustomobject]@{
        name=$Name; status=$Status; timestamp_utc=(Get-Date).ToUniversalTime().ToString('o')
        command=$Command; evidence=$Evidence; remediation=$Remediation
    })
}
try {
    $os = Get-CimInstance Win32_OperatingSystem
    Add-Check 'Host OS' 'PASS' 'Get-CimInstance Win32_OperatingSystem' "$($os.Caption); version $($os.Version); architecture $($os.OSArchitecture)"
} catch { Add-Check 'Host OS' 'FAIL' 'Get-CimInstance Win32_OperatingSystem' $_.Exception.Message 'Run from a Windows PowerShell session with CIM access.' }
try {
    $cpu = @(Get-CimInstance Win32_Processor)
    $cores = ($cpu | Measure-Object -Property NumberOfCores -Sum).Sum
    $virtOk = ($cpu.Count -gt 0) -and (@($cpu | Where-Object { -not $_.VirtualizationFirmwareEnabled }).Count -eq 0)
    $evidence = "CPU packages=$($cpu.Count); cores=$cores; virtualizationFirmwareEnabled=$(@($cpu | Where-Object VirtualizationFirmwareEnabled).Count -eq $cpu.Count); SLAT=$(@($cpu | Where-Object SecondLevelAddressTranslationExtensions).Count -eq $cpu.Count)"
    Add-Check 'Firmware virtualization' $(if ($virtOk) {'PASS'} else {'FAIL'}) 'Get-CimInstance Win32_Processor' $evidence 'Enable Intel VT-x/AMD-V and SLAT in firmware/BIOS, then re-run.'
} catch { Add-Check 'Firmware virtualization' 'NOT RUN' 'Get-CimInstance Win32_Processor' $_.Exception.Message 'Check Windows CIM access.' }
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $ramGiB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    Add-Check 'Host memory' $(if ($ramGiB -ge 20) {'PASS'} else {'FAIL'}) 'Get-CimInstance Win32_ComputerSystem' "Total RAM=${ramGiB} GiB" 'The YAML contains example sizing only; reduce allocations or add RAM if the real host is undersized.'
} catch { Add-Check 'Host memory' 'NOT RUN' 'Get-CimInstance Win32_ComputerSystem' $_.Exception.Message }
try {
    $drive = Get-PSDrive -Name ([System.IO.Path]::GetPathRoot((Get-Location).Path).Substring(0,1)) -ErrorAction Stop
    $freeGiB = [math]::Round($drive.Free / 1GB, 2)
    Add-Check 'Current-drive free space' $(if ($freeGiB -ge 150) {'PASS'} else {'FAIL'}) 'Get-PSDrive' "Free=${freeGiB} GiB on current drive" 'Check the actual VM storage location and allow capacity for two Proxmox disks plus guest disks.'
} catch { Add-Check 'Current-drive free space' 'NOT RUN' 'Get-PSDrive' $_.Exception.Message 'Set the shell to the drive that will store the VMs and re-run.' }
$vmwareCandidates = @(
    (Get-Command vmware.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
    (Get-Command vmrun.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source),
    "$env:ProgramFiles(x86)\VMware\VMware Workstation\vmware.exe",
    "$env:ProgramFiles\VMware\VMware Workstation\vmware.exe",
    "$env:ProgramFiles(x86)\VMware\VMware Player\vmplayer.exe",
    "$env:ProgramFiles\VMware\VMware Player\vmplayer.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
if ($vmwareCandidates.Count -gt 0) {
    Add-Check 'VMware installed' 'PASS' 'Get-Command / standard install paths' ($vmwareCandidates -join '; ')
} else {
    Add-Check 'VMware installed' 'FAIL' 'Get-Command / standard install paths' 'No VMware Workstation/Player executable found in common locations.' 'Install a supported VMware Workstation edition, then re-run.'
}
Add-Check 'Nested virtualization exposure' 'NOT RUN' 'VMware VM Settings > Processors > Virtualize Intel VT-x/EPT or AMD-V/RVI' 'Must be enabled separately for both new Proxmox VMs; host firmware support does not prove it is enabled in the nested guests.' 'Open both VM settings and enable nested virtualization before the Proxmox install.'
Add-Check 'LAN/IP reservation state' 'NOT RUN' 'Router/DHCP reservations + check-ip-conflicts.ps1' 'Not observable from this script; a failed ping alone is insufficient.' 'Verify 192.168.1.111 and 192.168.1.112 in authoritative DHCP/router records.'
$root = Split-Path -Parent $ReportPath
if ($root) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
$summary = [pscustomobject]@{ generated_at_utc=(Get-Date).ToUniversalTime().ToString('o'); host=$env:COMPUTERNAME; checks=@($checks); status=$(if (@($checks | Where-Object status -eq 'FAIL').Count -gt 0) {'FAIL'} elseif (@($checks | Where-Object status -eq 'NOT RUN').Count -gt 0) {'BLOCKED'} else {'PASS'}) }
$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $ReportPath
$checks | Format-Table name,status,evidence -AutoSize
Write-Host "Report: $ReportPath"
if ($summary.status -ne 'PASS') { exit 2 }
