# Installs Windows Media Foundation components required by AIMS (webrtc, record, audioplayers).
# Run during setup with administrator privileges.

$ErrorActionPreference = 'Continue'

function Test-MediaFoundation {
    $sys = Join-Path $env:WINDIR 'System32'
    return (
        (Test-Path (Join-Path $sys 'mf.dll')) -and
        (Test-Path (Join-Path $sys 'MFPlat.DLL')) -and
        (Test-Path (Join-Path $sys 'MFReadWrite.dll'))
    )
}

function Write-Log([string]$Message) {
    Write-Host "[AIMS] $Message"
}

if (Test-MediaFoundation) {
    Write-Log 'Windows Media components already present.'
    exit 0
}

Write-Log 'Windows Media components missing — attempting automatic install...'

$capabilities = @(
    'Media.WindowsMediaPlayer~~~~0.0.12.0',
    'Media.WindowsMediaPlayer~~~~0.0.11.0',
    'Media.WindowsMediaPlayer~~~~0.0.10.0'
)

foreach ($cap in $capabilities) {
    Write-Log "Trying capability: $cap"
    $null = & dism.exe /online /add-capability /capabilityname:$cap /quiet /norestart 2>&1
    if ((Test-MediaFoundation)) {
        Write-Log "Media components installed via DISM ($cap)."
        exit 0
    }
}

if (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue) {
    foreach ($cap in $capabilities) {
        Write-Log "Trying Add-WindowsCapability: $cap"
        try {
            $state = Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue
            if ($state -and $state.State -ne 'Installed') {
                Add-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {
            # Continue to next capability name.
        }
        if (Test-MediaFoundation) {
            Write-Log "Media components installed via Add-WindowsCapability ($cap)."
            exit 0
        }
    }
}

$msg = @"
AIMS could not install Windows Media components automatically.

This is common on Windows N / KN editions.

Please install the Microsoft Media Feature Pack, restart your PC, then run AIMS again:
https://www.microsoft.com/en-us/software-download/mediafeaturepack

Or enable "Media Feature Pack" / "Windows Media Player" under:
Settings → Apps → Optional features → View features
"@

Write-Log $msg

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    [System.Windows.Forms.MessageBox]::Show(
        $msg,
        'AIMS Setup — Media components',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
} catch {
    # Headless / no UI — installer log only.
}

exit 1
