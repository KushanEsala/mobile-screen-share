[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Find-ScrcpyDirectory {
    $command = Get-Command 'scrcpy' -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return Split-Path -Parent $command.Source
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (-not (Test-Path -LiteralPath $packageRoot)) {
        return $null
    }

    $packageDirectories = Get-ChildItem -LiteralPath $packageRoot -Directory -Filter 'Genymobile.scrcpy_*' -ErrorAction SilentlyContinue
    $executables = foreach ($packageDirectory in $packageDirectories) {
        Get-ChildItem -LiteralPath $packageDirectory.FullName -File -Filter 'scrcpy.exe' -Recurse -ErrorAction SilentlyContinue
    }

    $executable = $executables | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($executable) {
        return $executable.DirectoryName
    }

    return $null
}

function Install-Scrcpy {
    $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'WinGet is unavailable. Install Microsoft App Installer from the Microsoft Store, then run this launcher again.'
    }

    Write-Step 'Installing official scrcpy and ADB with WinGet'
    & $winget.Source install --exact --id Genymobile.scrcpy --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet could not install scrcpy (exit code $LASTEXITCODE)."
    }
}

function Invoke-AdbCommand {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    # ADB writes routine daemon startup messages to stderr. Windows PowerShell
    # turns those lines into error records, so temporarily allow native stderr
    # and decide success from ADB's exit code instead.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $AdbPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { $_.ToString() })
    }
}

function Start-AdbServer {
    param([Parameter(Mandatory)][string]$AdbPath)

    $lastResult = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($attempt -gt 1) {
            $null = Invoke-AdbCommand -AdbPath $AdbPath -Arguments @('kill-server')
            Start-Sleep -Seconds 1
        }

        $lastResult = Invoke-AdbCommand -AdbPath $AdbPath -Arguments @('start-server')
        if ($lastResult.ExitCode -eq 0) {
            return
        }

        Start-Sleep -Seconds 1
    }

    $details = ($lastResult.Output -join ' ').Trim()
    if (-not $details) {
        $details = "exit code $($lastResult.ExitCode)"
    }
    throw "ADB server could not start after 3 attempts: $details"
}

function Get-AdbDevices {
    param([Parameter(Mandatory)][string]$AdbPath)

    $result = Invoke-AdbCommand -AdbPath $AdbPath -Arguments @('devices')
    if ($result.ExitCode -ne 0) {
        $details = ($result.Output -join ' ').Trim()
        throw "ADB could not check the connected devices: $details"
    }

    $devices = foreach ($line in $result.Output) {
        if ($line -match '^(?<Serial>\S+)\s+(?<State>device|unauthorized|offline)\s*$') {
            [pscustomobject]@{
                Serial = $Matches.Serial
                State  = $Matches.State
            }
        }
    }

    return @($devices)
}

function Wait-ForAuthorizedPhone {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [int]$TimeoutSeconds = 300
    )

    Write-Step 'Waiting for one authorized Android phone over USB'
    Write-Host 'If this is the first connection:'
    Write-Host '  1. Unlock the phone.'
    Write-Host '  2. Enable Developer options and USB debugging.'
    Write-Host '  3. Tap Allow on the USB debugging prompt.'
    Write-Host 'The launcher will continue automatically.'

    Start-AdbServer -AdbPath $AdbPath
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastMessage = ''

    while ((Get-Date) -lt $deadline) {
        try {
            $devices = @(Get-AdbDevices -AdbPath $AdbPath)
        } catch {
            Write-Host 'ADB connection reset. Restarting it automatically...' -ForegroundColor Yellow
            Start-AdbServer -AdbPath $AdbPath
            Start-Sleep -Seconds 1
            continue
        }
        $authorized = @($devices | Where-Object State -eq 'device')
        $unauthorized = @($devices | Where-Object State -eq 'unauthorized')

        if ($authorized.Count -eq 1) {
            Write-Host 'Phone authorized.' -ForegroundColor Green
            return
        }

        if ($authorized.Count -gt 1) {
            throw 'More than one authorized Android device is connected. Disconnect the extra devices and run the launcher again.'
        }

        $message = if ($unauthorized.Count -gt 0) {
            'Phone detected. Unlock it and tap Allow on the USB debugging prompt.'
        } else {
            'No authorized phone yet. Connect the USB data cable and enable USB debugging.'
        }

        if ($message -ne $lastMessage) {
            Write-Host $message -ForegroundColor Yellow
            $lastMessage = $message
        }

        Start-Sleep -Seconds 2
    }

    throw "No authorized phone was available after $TimeoutSeconds seconds. Check the cable, USB debugging, and the authorization prompt."
}

try {
    $scrcpyDirectory = Find-ScrcpyDirectory
    if (-not $scrcpyDirectory) {
        Install-Scrcpy
        $scrcpyDirectory = Find-ScrcpyDirectory
    }

    if (-not $scrcpyDirectory) {
        throw 'scrcpy was installed but its executable could not be located. Close this window and run the launcher again.'
    }

    $scrcpyPath = Join-Path $scrcpyDirectory 'scrcpy.exe'
    $adbPath = Join-Path $scrcpyDirectory 'adb.exe'

    if (-not (Test-Path -LiteralPath $scrcpyPath)) {
        throw "scrcpy.exe is missing from $scrcpyDirectory."
    }
    if (-not (Test-Path -LiteralPath $adbPath)) {
        throw "adb.exe is missing from $scrcpyDirectory."
    }

    if ($ValidateOnly) {
        Write-Host 'Validation passed: scrcpy and ADB are available.' -ForegroundColor Green
        exit 0
    }

    while ($true) {
        Wait-ForAuthorizedPhone -AdbPath $adbPath

        Write-Step 'Starting the mirror in lock-screen compatible mode'
        Write-Host 'The phone remains powered on and controllable from the laptop.'
        Write-Host 'Android input injection is enabled for better password-field compatibility.'
        Write-Host 'After unlocking: Alt+O turns the phone display off; Alt+Shift+O turns it on.'

        Push-Location $scrcpyDirectory
        try {
            & $scrcpyPath --select-usb --no-audio --keyboard=sdk --mouse=sdk --prefer-text --keep-active
            $scrcpyExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }

        if ($scrcpyExitCode -eq 0) {
            break
        }

        Write-Host "`nThe mirror connection ended. Waiting for the phone to reconnect after USB interruption or reboot..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

exit 0
