# Installs Microsoft Visual C++ 2015-2022 Redistributable (x64) if needed.

param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath
)

$ErrorActionPreference = 'Continue'

function Test-VcRedistInstalled {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    )
    foreach ($key in $keys) {
        if (Test-Path $key) {
            $installed = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).Installed
            if ($installed -eq 1) { return $true }
        }
    }
    return $false
}

if (Test-VcRedistInstalled) {
    Write-Host '[AIMS] Visual C++ Runtime already installed.'
    exit 0
}

if (-not (Test-Path $InstallerPath)) {
    Write-Host "[AIMS] VC++ installer not found: $InstallerPath"
    exit 1
}

Write-Host '[AIMS] Installing Visual C++ Runtime...'
$proc = Start-Process -FilePath $InstallerPath -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 1638 -or $proc.ExitCode -eq 3010) {
    Write-Host '[AIMS] Visual C++ Runtime install finished.'
    exit 0
}

Write-Host "[AIMS] VC++ installer exit code: $($proc.ExitCode)"
exit $proc.ExitCode
