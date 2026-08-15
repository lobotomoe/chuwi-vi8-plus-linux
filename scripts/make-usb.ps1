<#
.SYNOPSIS
    Build a USB stick that a 32-bit UEFI tablet will actually boot.

.DESCRIPTION
    GPT -> one FAT32 partition -> contents of the ISO copied onto it ->
    artifacts\bootia32.efi dropped into \EFI\BOOT\.

    The ISO is copied rather than written with dd, because a dd-written ISO9660
    filesystem is read-only and bootia32.efi could never be added to it.
    See docs\02-boot-problem.md.

    This is the scripted equivalent of "Rufus in ISO image mode, then drag
    bootia32.efi onto the stick". If you prefer a GUI, use Rufus - see
    docs\12-usb-windows.md.

    Must be run from an elevated PowerShell. DESTROYS the target disk.

.EXAMPLE
    Get-Disk
    .\make-usb.ps1 -IsoPath C:\iso\lubuntu-26.04-desktop-amd64.iso -DiskNumber 2 -Sha256 abc123...
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$IsoPath,
    [Parameter(Mandatory = $true)][int]$DiskNumber,
    [string]$Sha256,
    [string]$Bootia32Path = (Join-Path $PSScriptRoot '..\artifacts\bootia32.efi'),
    [string]$Label = 'VI8PLUS',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Windows' own FAT32 formatter refuses volumes above this size.
$FAT32_MAX_VOLUME_BYTES = 32GB

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this from an elevated PowerShell (Run as administrator).'
    }
}

Assert-Admin

if (-not (Test-Path -LiteralPath $IsoPath)) { throw "No such ISO: $IsoPath" }
if (-not (Test-Path -LiteralPath $Bootia32Path)) { throw "No such bootia32: $Bootia32Path" }
if ($Label.Length -gt 11) { throw "FAT32 labels are 11 characters at most: $Label" }

$IsoPath = (Resolve-Path -LiteralPath $IsoPath).Path
$Bootia32Path = (Resolve-Path -LiteralPath $Bootia32Path).Path

# The ISO is the one thing here that ends up executing as root on the tablet, so
# check it before the stick is destroyed rather than after.
if ($Sha256) {
    Write-Host 'Verifying the ISO checksum (reads the whole image)...'
    $actual = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
    if ($actual -ne $Sha256.Trim().ToUpperInvariant()) {
        throw "SHA-256 mismatch - do not use this image.`n  expected: $Sha256`n  actual:   $actual"
    }
    Write-Host 'ISO checksum OK.'
}
else {
    Write-Warning 'No -Sha256 given; the ISO is being used unverified.'
}

# ---------------------------------------------------------------------------
# Safety: describe the target and make the operator type it back
# ---------------------------------------------------------------------------

$disk = Get-Disk -Number $DiskNumber
$disk | Format-List Number, FriendlyName, SerialNumber, BusType, Size, IsBoot, IsSystem |
    Out-String | Write-Host

if ($disk.IsBoot -or $disk.IsSystem) {
    throw "Disk $DiskNumber is the boot/system disk. Refusing."
}
if (-not $Force -and $disk.BusType -ne 'USB') {
    throw "Disk $DiskNumber is not USB-attached (BusType: $($disk.BusType)). Use -Force if you are certain."
}
if ($disk.Size -gt $FAT32_MAX_VOLUME_BYTES) {
    throw ("Disk $DiskNumber is {0:N0} bytes. Windows cannot format FAT32 volumes above 32 GB. " +
           'Use a smaller stick, or use Rufus (docs\12-usb-windows.md).') -f $disk.Size
}

Write-Host "Everything on disk $DiskNumber will be destroyed."
$answer = Read-Host "Type ERASE $DiskNumber to continue"
if ($answer -ne "ERASE $DiskNumber") { throw "Aborted (got '$answer')" }

# ---------------------------------------------------------------------------
# Partition and format
# ---------------------------------------------------------------------------

Write-Host "Partitioning disk $DiskNumber (GPT, one FAT32 partition, label $Label)..."

# Clear-Disk throws on a disk that is already RAW, which is exactly what a
# freshly wiped stick looks like. Only clear what there is to clear.
if ($disk.PartitionStyle -ne 'RAW') {
    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
}
Initialize-Disk -Number $DiskNumber -PartitionStyle GPT -Confirm:$false

$partition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
Format-Volume -Partition $partition -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false | Out-Null

# The object New-Partition returns is a snapshot: the mount manager assigns the
# drive letter asynchronously, so DriveLetter on it is often still empty. Re-read
# the partition until the letter appears rather than building a path from NUL.
$driveLetter = $null
foreach ($attempt in 1..10) {
    $driveLetter = (Get-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber).DriveLetter
    if ($driveLetter -and $driveLetter -ne [char]0) { break }
    Start-Sleep -Milliseconds 500
}
if (-not $driveLetter -or $driveLetter -eq [char]0) {
    throw "Windows did not assign a drive letter to the new partition on disk $DiskNumber."
}

$usbRoot = "${driveLetter}:\"
Write-Host "Stick mounted at $usbRoot"

# ---------------------------------------------------------------------------
# Copy the ISO contents
# ---------------------------------------------------------------------------

$image = Mount-DiskImage -ImagePath $IsoPath -PassThru
try {
    $isoLetter = ($image | Get-Volume).DriveLetter
    if (-not $isoLetter) { throw "Windows could not mount $IsoPath" }
    $isoRoot = "${isoLetter}:\"

    $oversized = Get-ChildItem -LiteralPath $isoRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 4GB } | Select-Object -First 3
    if ($oversized) {
        $oversized | ForEach-Object { Write-Host $_.FullName }
        throw ('The image contains files of 4 GB or more, which FAT32 cannot store. ' +
               'Use Ventoy - see docs\12-usb-windows.md.')
    }

    Write-Host 'Copying to the stick (this is the slow part)...'
    robocopy $isoRoot $usbRoot /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    # robocopy uses exit codes 0-7 for success, 8 and above for failure.
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
}
finally {
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
}

# ---------------------------------------------------------------------------
# Install the 32-bit bootloader
# ---------------------------------------------------------------------------

$efiBoot = Join-Path $usbRoot 'EFI\BOOT'
if (-not (Test-Path -LiteralPath $efiBoot)) {
    New-Item -ItemType Directory -Path $efiBoot -Force | Out-Null
}

$existing = Get-ChildItem -LiteralPath $efiBoot -Filter 'bootia32.efi' -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host 'The ISO already ships bootia32.efi - leaving it in place.'
    Write-Host 'This image boots 32-bit firmware on its own.'
}
else {
    Copy-Item -LiteralPath $Bootia32Path -Destination (Join-Path $efiBoot 'bootia32.efi') -Force
    Write-Host 'Installed bootia32.efi into \EFI\BOOT\'
}

# artifacts\bootia32.efi looks for \boot\grub\grub.cfg. Some GRUB builds instead
# resolve $prefix\<cpu>-efi\grub.cfg; this one-line file satisfies both.
if (Test-Path -LiteralPath (Join-Path $usbRoot 'boot\grub\grub.cfg')) {
    $redirectDir = Join-Path $usbRoot 'boot\grub\i386-efi'
    New-Item -ItemType Directory -Path $redirectDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $redirectDir 'grub.cfg') `
        -Value 'source /boot/grub/grub.cfg' -Encoding ascii -NoNewline:$false
}

Get-ChildItem -LiteralPath $efiBoot | Format-Table Name, Length | Out-String | Write-Host

Write-Host ''
Write-Host 'Done. Stick is ready.'
Write-Host 'Next: docs\20-uefi-setup.md - disable Secure Boot, then boot it from the tablet.'
