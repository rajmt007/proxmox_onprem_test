[CmdletBinding()]
param(
    [string]$VMRootPath = '',
    [string]$ProxmoxISO = '',
    [string]$VmwareVdiskManager = '',
    [int]$CpuCores = 4,
    [int]$MemoryMiB = 8192,
    [int]$DiskSizeGiB = 64,
    [string]$NetworkMode = 'bridged',
    [string]$VmxHardwareVersion = '',
    [switch]$Apply,
    [switch]$ConfirmShellCreation,
    [switch]$ConfirmTargetIpAvailability
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $VMRootPath) { Write-Error 'BLOCKED: specify -VMRootPath as an existing, dedicated folder for new VMs.'; exit 2 }
if (-not (Test-Path -LiteralPath $VMRootPath -PathType Container)) { Write-Error "BLOCKED: VMRootPath does not exist: $VMRootPath"; exit 2 }
if (-not $ProxmoxISO -or -not (Test-Path -LiteralPath $ProxmoxISO -PathType Leaf)) { Write-Error 'BLOCKED: specify the existing official Proxmox ISO path with -ProxmoxISO.'; exit 2 }
if ($CpuCores -lt 2 -or $MemoryMiB -lt 4096 -or $DiskSizeGiB -lt 32) { Write-Error 'BLOCKED: each nested node must have at least 2 vCPU, 4096 MiB RAM, and 32 GiB disk; consider larger lab sizing.'; exit 2 }
if ($NetworkMode -notin @('bridged','nat')) { Write-Error 'BLOCKED: NetworkMode must be bridged or nat; static LAN node IPs normally require a verified design.'; exit 2 }
if (-not $VmxHardwareVersion -or $VmxHardwareVersion -notmatch '^\d{1,2}$') { Write-Error 'BLOCKED: set -VmxHardwareVersion to a hardware version supported by the installed VMware edition.'; exit 2 }
if (-not $VmwareVdiskManager) {
    $cmd = Get-Command vmware-vdiskmanager.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $VmwareVdiskManager = $cmd.Source }
    else {
        $paths = @("$env:ProgramFiles(x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe", "$env:ProgramFiles\VMware\VMware Workstation\vmware-vdiskmanager.exe")
        $VmwareVdiskManager = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
}
if (-not $VmwareVdiskManager -or -not (Test-Path -LiteralPath $VmwareVdiskManager -PathType Leaf)) { Write-Error 'BLOCKED: vmware-vdiskmanager.exe was not found; set -VmwareVdiskManager explicitly.'; exit 2 }
$targets = @(
    [pscustomobject]@{ Name='pve01'; IP='192.168.1.111' },
    [pscustomobject]@{ Name='pve02'; IP='192.168.1.112' }
)
foreach ($target in $targets) {
    $path = Join-Path $VMRootPath $target.Name
    $disk = Join-Path $path "$($target.Name).vmdk"
    $vmx = Join-Path $path "$($target.Name).vmx"
    Write-Host "Target VM: $($target.Name)"
    Write-Host "  VM folder: $path"
    Write-Host "  Virtual disk: $disk ($DiskSizeGiB GiB; Proxmox installation will erase this disk)"
    Write-Host "  ISO: $([System.IO.Path]::GetFullPath($ProxmoxISO))"
    Write-Host "  Requested target IP: $($target.IP) (not confirmed available)"
    Write-Host "  Resources: CPU=$CpuCores vCPU; RAM=$MemoryMiB MiB; Network=$NetworkMode"
    if (Test-Path -LiteralPath $path) { Write-Error "BLOCKED: VM folder already exists; preserving it: $path"; exit 2 }
}
if (-not $ConfirmTargetIpAvailability) {
    Write-Error 'BLOCKED: first run check-ip-conflicts.ps1, inspect Envir inventory, and verify both target IPs in your DHCP/router reservation system. Re-run with -ConfirmTargetIpAvailability only after that external check passes.'
    exit 2
}
$ipCheck = Join-Path $PSScriptRoot 'check-ip-conflicts.ps1'
$ipReportDir = Join-Path $root 'reports/generated'
$engine = (Get-Process -Id $PID).Path
$ipOutput = & $engine -NoProfile -ExecutionPolicy Bypass -File $ipCheck -TargetIP '192.168.1.111','192.168.1.112' -ReportDirectory $ipReportDir 2>&1
$ipCheckExit = $LASTEXITCODE
$latest = Get-ChildItem -Path $ipReportDir -Filter 'ip-conflicts-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    $state = Get-Content -Raw -LiteralPath $latest.FullName | ConvertFrom-Json
    if (@($state | Where-Object status -eq 'CONFLICT').Count -gt 0) { Write-Error 'BLOCKED: ping/neighbour evidence suggests a target IP conflict; do not continue.'; exit 2 }
}
# The script's status remains UNKNOWN_BLOCKED when LAN/DHCP APIs are unavailable. Proceeding requires the explicit external confirmation above.
$inventoryResult = & python (Join-Path $PSScriptRoot 'inventory_check.py') --path 'inventory/environment-inventory.xlsx' --worksheet Envir --target-ip '192.168.1.111' --target-ip '192.168.1.112' --repo-root $root
if ($LASTEXITCODE -ne 0) { Write-Error "BLOCKED: inventory scan failed or an active record matches a target IP. $inventoryResult"; exit 2 }
if (-not $Apply) { Write-Host 'DRY RUN: all requested VM shell inputs passed. No VM folders/disks created. Use -Apply -ConfirmShellCreation after reviewing the output.'; exit 0 }
if (-not $ConfirmShellCreation) { Write-Error 'BLOCKED: -ConfirmShellCreation is required with -Apply.'; exit 2 }
$phrase = 'CREATE PROXMOX VM SHELLS pve01 pve02'
$typed = Read-Host "Type exactly '$phrase' to continue"
if ($typed -cne $phrase) { Write-Error 'Confirmation did not match. No VM shells created.'; exit 2 }
$iso = [System.IO.Path]::GetFullPath($ProxmoxISO).Replace('\','\\')
foreach ($target in $targets) {
    $path = Join-Path $VMRootPath $target.Name
    $disk = Join-Path $path "$($target.Name).vmdk"
    $vmx = Join-Path $path "$($target.Name).vmx"
    New-Item -ItemType Directory -Path $path | Out-Null
    & $VmwareVdiskManager -c -s "${DiskSizeGiB}GB" -a lsilogic -t 0 $disk
    if ($LASTEXITCODE -ne 0) { Write-Error "Disk creation failed for $($target.Name). Stop and inspect $path; no automatic cleanup was run."; exit 2 }
    $connection = if ($NetworkMode -eq 'bridged') { 'bridged' } else { 'nat' }
    $vmxLines = @(
        'config.version = "8"',
        "virtualHW.version = `"$VmxHardwareVersion`"",
        'displayName = "' + $target.Name + '"',
        'guestOS = "debian12-64"',
        "memsize = `"$MemoryMiB`"",
        "numvcpus = `"$CpuCores`"",
        'cpuid.coresPerSocket = "2"',
        'vhv.enable = "TRUE"',
        'scsi0.present = "TRUE"',
        'scsi0.virtualDev = "lsilogic"',
        'scsi0:0.present = "TRUE"',
        'scsi0:0.deviceType = "scsi-hardDisk"',
        'scsi0:0.fileName = "' + [System.IO.Path]::GetFileName($disk) + '"',
        'ide1:0.present = "TRUE"',
        'ide1:0.deviceType = "cdrom-image"',
        'ide1:0.fileName = "' + $iso + '"',
        'ethernet0.present = "TRUE"',
        'ethernet0.connectionType = "' + $connection + '"',
        'ethernet0.virtualDev = "e1000e"',
        'ethernet0.addressType = "generated"',
        'usb.present = "TRUE"',
        'sound.present = "FALSE"',
        'mks.enable3d = "FALSE"',
        'uuid.action = "create"'
    )
    $vmxLines | Set-Content -LiteralPath $vmx -Encoding Ascii
    Write-Host "Created VM shell only: $vmx"
    Write-Host "  Dedicated disk: $disk ($DiskSizeGiB GiB)"
    Write-Host '  Not installed: boot the VM only after rechecking selected disk, ISO, target IP and reservation evidence.'
}
Write-Host 'VM shell creation completed. Proxmox is NOT installed. Review each .vmx in VMware UI and verify nested virtualization is enabled.'
