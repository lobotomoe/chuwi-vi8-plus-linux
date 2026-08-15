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

# Windows' own FAT32 formatter refuses to create volumes above 32 GB. That is a
# limit on the volume, not on the stick: a larger stick is used by partitioning a
# slice under the limit and leaving the remainder unallocated. 31 GB keeps a
# margin below the threshold, and no installer image comes close to filling it.
$FAT32_MAX_VOLUME_BYTES = 32GB
$FAT32_SLICE_BYTES = 31GB

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

# The committed artifact has a recorded checksum, and a stick built from a damaged
# copy boots nothing at all. Only the repository's own file is checked: a
# -Bootia32Path the operator supplied is theirs to vouch for.
$defaultBootia32 = (Join-Path $PSScriptRoot '..\artifacts\bootia32.efi')
$sha256Sums = (Join-Path $PSScriptRoot '..\artifacts\SHA256SUMS')
if ((Test-Path -LiteralPath $defaultBootia32) -and
    $Bootia32Path -eq (Resolve-Path -LiteralPath $defaultBootia32).Path -and
    (Test-Path -LiteralPath $sha256Sums)) {
    $recorded = Select-String -LiteralPath $sha256Sums -Pattern '^\s*([0-9A-Fa-f]{64})\s+\*?bootia32\.efi\s*$' |
        Select-Object -First 1
    if ($recorded) {
        $expectedBoot = $recorded.Matches[0].Groups[1].Value.ToUpperInvariant()
        $actualBoot = (Get-FileHash -LiteralPath $Bootia32Path -Algorithm SHA256).Hash
        if ($actualBoot -ne $expectedBoot) {
            throw ("artifacts\bootia32.efi does not match artifacts\SHA256SUMS.`n" +
                   "  expected: $expectedBoot`n  actual:   $actualBoot`n" +
                   'Check the file out again, or re-derive it with scripts/fetch-bootia32.sh.')
        }
    }
}

# The ISO is the one thing here that ends up executing as root on the tablet, so
# check it before the stick is destroyed rather than after.
if ($Sha256) {
    # Reject anything that is not a bare digest up front. Pasting a whole
    # SHA256SUMS line is the common slip, and comparing it would raise a
    # tampering alarm over what is really a copy-paste mistake.
    $expected = $Sha256.Trim()
    if ($expected -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "-Sha256 takes only the 64-character digest, not the whole SHA256SUMS line: $Sha256"
    }
    Write-Host 'Verifying the ISO checksum (reads the whole image)...'
    $actual = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256).Hash
    if ($actual -ne $expected.ToUpperInvariant()) {
        throw "SHA-256 mismatch - do not use this image.`n  expected: $expected`n  actual:   $actual"
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
# Sticks are rarely smaller than 64 GB now, so refusing them outright would make
# this script useless on the common case. Take a slice instead.
$useMaximumSize = $disk.Size -le $FAT32_MAX_VOLUME_BYTES
if (-not $useMaximumSize) {
    $sliceMessage = (
        'Disk is {0:N1} GB. Windows cannot format FAT32 above 32 GB, so a {1:N0} GB ' +
        'partition will be created and the remainder left unallocated - ample for any ' +
        'installer image. Use Rufus or Ventoy if you want the whole stick as one volume.'
    ) -f ($disk.Size / 1GB), ($FAT32_SLICE_BYTES / 1GB)
    Write-Host $sliceMessage
}

# Whichever of the two it is, the ISO still has to fit in it. Checked here, while
# the stick is untouched, rather than discovered when the copy runs out of room.
if ($useMaximumSize) { $capacityBytes = $disk.Size } else { $capacityBytes = $FAT32_SLICE_BYTES }
$isoBytes = (Get-Item -LiteralPath $IsoPath).Length
# FAT32 metadata and per-file slack make the usable space meaningfully smaller
# than the partition, so require real headroom rather than a bare fit.
if ($isoBytes -gt ($capacityBytes * 0.95)) {
    $fitMessage = (
        'The ISO is {0:N1} GB and the FAT32 partition would be {1:N1} GB. ' +
        'It will not fit. Use a larger stick.'
    ) -f ($isoBytes / 1GB), ($capacityBytes / 1GB)
    throw $fitMessage
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

$partition = if ($useMaximumSize) {
    New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
}
else {
    New-Partition -DiskNumber $DiskNumber -Size $FAT32_SLICE_BYTES -AssignDriveLetter
}
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
    # robocopy uses exit codes 0-7 for success (1 = "files were copied", the
    # normal outcome here). PowerShell 7.4+ defaults
    # $PSNativeCommandUseErrorActionPreference to $true, which turns any non-zero
    # exit into a terminating error under $ErrorActionPreference = 'Stop' - so a
    # successful copy would throw. Suppress that for this one call and judge the
    # exit code ourselves. Setting the variable is harmless on Windows PowerShell
    # 5.1, where it does not exist.
    & {
        $PSNativeCommandUseErrorActionPreference = $false
        robocopy $isoRoot $usbRoot /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    }
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
    # Written with an explicit LF: Set-Content would end the line with CRLF, and
    # a stray carriage return becomes part of the path GRUB tries to source.
    # This also keeps the stick byte-identical to one built by make-usb.sh.
    [System.IO.File]::WriteAllText(
        (Join-Path $redirectDir 'grub.cfg'),
        "source /boot/grub/grub.cfg`n",
        [System.Text.UTF8Encoding]::new($false))
}

Get-ChildItem -LiteralPath $efiBoot | Format-Table Name, Length | Out-String | Write-Host

Write-Host ''
Write-Host 'Done. Stick is ready.'
Write-Host 'Next: docs\20-uefi-setup.md - disable Secure Boot, then boot it from the tablet.'
