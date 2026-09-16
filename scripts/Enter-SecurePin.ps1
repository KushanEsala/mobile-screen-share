[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-AdbPath {
    $command = Get-Command 'adb.exe' -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (-not (Test-Path -LiteralPath $packageRoot)) {
        return $null
    }

    $adb = Get-ChildItem -LiteralPath $packageRoot -Filter 'adb.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($adb) {
        return $adb.FullName
    }

    return $null
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

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

function Get-UiDocument {
    param([Parameter(Mandatory)][string]$AdbPath)

    $remotePath = '/data/local/tmp/pc-unlock-window.xml'
    $dump = Invoke-Adb -AdbPath $AdbPath -Arguments @('shell', 'uiautomator', 'dump', $remotePath)
    if ($dump.ExitCode -ne 0) {
        throw "Android could not inspect the current screen: $($dump.Output -join ' ')"
    }

    try {
        $read = Invoke-Adb -AdbPath $AdbPath -Arguments @('shell', 'cat', $remotePath)
        if ($read.ExitCode -ne 0) {
            throw "Android could not read the current screen: $($read.Output -join ' ')"
        }
        return [xml]($read.Output -join "`n")
    } finally {
        $null = Invoke-Adb -AdbPath $AdbPath -Arguments @('shell', 'rm', '-f', $remotePath)
    }
}

function Get-NodeCenter {
    param([Parameter(Mandatory)]$Node)

    $bounds = [string]$Node.GetAttribute('bounds')
    if ($bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
        return $null
    }

    [pscustomobject]@{
        X = [int](($Matches[1] -as [int]) + ($Matches[3] -as [int])) / 2
        Y = [int](($Matches[2] -as [int]) + ($Matches[4] -as [int])) / 2
    }
}

function Get-KeypadPositions {
    param([Parameter(Mandatory)][xml]$Document)

    $positions = @{}
    foreach ($digit in 0..9) {
        $candidates = foreach ($node in $Document.SelectNodes('//node')) {
            $label = [string]$node.GetAttribute('content-desc')
            if (-not $label) {
                $label = [string]$node.GetAttribute('text')
            }

            if ($label -eq [string]$digit -and $node.GetAttribute('clickable') -eq 'true') {
                $center = Get-NodeCenter -Node $node
                if ($center) {
                    $center
                }
            }
        }

        $position = @($candidates | Sort-Object Y -Descending | Select-Object -First 1)
        if ($position.Count -eq 1) {
            $positions[[string]$digit] = $position[0]
        }
    }

    return $positions
}

function Show-NumericKeypad {
    param(
        [Parameter(Mandatory)][string]$AdbPath,
        [Parameter(Mandatory)][xml]$Document
    )

    foreach ($node in $Document.SelectNodes('//node')) {
        $label = (([string]$node.GetAttribute('text')) + ' ' + ([string]$node.GetAttribute('content-desc'))).Trim()
        if ($node.GetAttribute('clickable') -eq 'true' -and $label -match '(?i)use (privacy )?(password|pin)') {
            $center = Get-NodeCenter -Node $node
            if ($center) {
                $result = Invoke-Adb -AdbPath $AdbPath -Arguments @('shell', 'input', 'tap', [string]$center.X, [string]$center.Y)
                if ($result.ExitCode -eq 0) {
                    Start-Sleep -Milliseconds 700
                    return $true
                }
            }
        }
    }

    $swipe = Invoke-Adb -AdbPath $AdbPath -Arguments @('shell', 'input', 'swipe', '360', '1400', '360', '400', '300')
    Start-Sleep -Milliseconds 700
    return $swipe.ExitCode -eq 0
}

try {
    $adbPath = Find-AdbPath
    if (-not $adbPath) {
        throw 'ADB was not found. Run the phone mirror launcher once to install it.'
    }

    $state = Invoke-Adb -AdbPath $adbPath -Arguments @('get-state')
    if ($state.ExitCode -ne 0 -or ($state.Output -join '').Trim() -ne 'device') {
        throw 'No authorized Android phone is connected over USB.'
    }

    $null = Invoke-Adb -AdbPath $adbPath -Arguments @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    Start-Sleep -Milliseconds 500

    $document = Get-UiDocument -AdbPath $adbPath
    $positions = Get-KeypadPositions -Document $document
    if ($positions.Count -lt 10) {
        $null = Show-NumericKeypad -AdbPath $adbPath -Document $document
        $document = Get-UiDocument -AdbPath $adbPath
        $positions = Get-KeypadPositions -Document $document
    }

    if ($positions.Count -lt 10) {
        throw 'A complete numeric PIN keypad is not visible. Open the lock or App Lock PIN screen, then run this helper again.'
    }

    if ($ValidateOnly) {
        Write-Host 'Validation passed: the visible Android numeric keypad was detected.' -ForegroundColor Green
        exit 0
    }

    Write-Host 'Enter the numeric PIN below. It will not be displayed or saved.' -ForegroundColor Cyan
    $securePin = Read-Host 'PIN' -AsSecureString
    $pinPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePin)
    try {
        $pin = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pinPointer)
        if ($pin -notmatch '^\d{4,16}$') {
            throw 'The PIN must contain 4 to 16 digits.'
        }

        foreach ($digit in $pin.ToCharArray()) {
            $position = $positions[[string]$digit]
            $tap = Invoke-Adb -AdbPath $adbPath -Arguments @('shell', 'input', 'tap', [string]$position.X, [string]$position.Y)
            if ($tap.ExitCode -ne 0) {
                throw 'Android rejected a keypad tap.'
            }
            Start-Sleep -Milliseconds 140
        }
    } finally {
        if ($pinPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pinPointer)
        }
        $pin = $null
        $securePin = $null
    }

    Write-Host 'PIN entry sent to the visible Android keypad.' -ForegroundColor Green
    Start-Sleep -Seconds 2
    exit 0
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
