# Makes the rebuilt tvhome the TV's default HOME app, and proves it.
#
#   powershell -ExecutionPolicy Bypass -File set-default-home.ps1
#   powershell -ExecutionPolicy Bypass -File set-default-home.ps1 -Scan      # find the TV first
#
# Safe to run any number of times: it only sets the home preference, never installs or removes anything.
param(
    [string]$Ip = '192.168.1.50',
    [switch]$Scan
)
$ErrorActionPreference = 'Stop'
$adb = 'adb'
$PKG = 'com.ansub.tvhome'
$HOME_ACT = "$PKG/.MainActivity"

function Say($m) { Write-Host "== $m" }
# adb writes its failures ("device unauthorized") to stderr, and with
# $ErrorActionPreference = 'Stop' PowerShell would turn that into a fatal error.
function Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Argv)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { (& $adb @Argv 2>&1) } finally { $ErrorActionPreference = $prev }
}
function Sh([string]$cmd) { Adb @('-s', "$Ip`:5555", 'shell', $cmd) }

# --- find the TV ------------------------------------------------------------
# A sweep for open 5555: the Fire Stick answers on that port too, so whichever
# device reports a TCL model wins; an unauthorized answer is reported, not used.
function Find-Tv {
    param([string]$Subnet = '192.168.1.')
    Say "sweeping $Subnet`1-254 for open 5555"
    $wait = @{}
    foreach ($n in 1..254) {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.BeginConnect("$Subnet$n", 5555, $null, $null) | Out-Null
        $wait["$Subnet$n"] = $c
    }
    $deadline = (Get-Date).AddSeconds(3)
    $open = @()
    while ((Get-Date) -lt $deadline) {
        foreach ($k in @($wait.Keys)) {
            if ($wait[$k].Connected) { $open += $k; $wait.Remove($k) }
        }
        if ($wait.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }
    foreach ($k in $wait.Keys) { $wait[$k].Close() }
    foreach ($ip in $open) {
        Adb @('connect', "$ip`:5555") | Out-Null
    }
    Start-Sleep -Milliseconds 800
    foreach ($ip in $open) {
        $model = (Adb @('-s', "$ip`:5555", 'shell', 'getprop', 'ro.product.model')) -join ' '
        Write-Host "   $ip -> $($model.Trim())"
        if ($model -match 'unauthorized|offline|error') { continue }
        if ($model -match 'TCL|C06|SmartTV') { return $ip }
    }
    return $null
}

# --- connect ----------------------------------------------------------------
Adb @('connect', "$Ip`:5555") | Out-Null
Start-Sleep -Milliseconds 500
$state = (& $adb devices) | Where-Object { $_ -like "$Ip`:5555*" }
if (-not $state -or $state -match 'offline|unauthorized') {
    if ($Scan) {
        $found = Find-Tv
        if (-not $found) {
            throw "no reachable TV on the network: turn the TV on, keep it on the same Wi-Fi, ADB debugging on"
        }
        $Ip = $found
    } else {
        Adb @('disconnect', "$Ip`:5555") | Out-Null
        throw "$Ip is not answering on 5555 - if it moved, rerun with -Scan; if it is off, turn it on"
    }
}
Say "device state: $(((& $adb devices) | Where-Object { $_ -like "$Ip`:5555*" } | Select-Object -First 1))"

$installed = (Sh "pm path $PKG") -join ' '
if ($installed -notmatch 'package:') {
    throw "$PKG is not installed on $Ip - run install-tvhome.ps1 first"
}

# --- set the default --------------------------------------------------------
# Android 11 keeps the home app in the role store; the older preference and the
# system setting are set as well so nothing (TCL guard included) reads a stale one.
Say "setting $HOME_ACT as the default home app"
Sh "cmd role add-role-holder --user 0 android.app.role.HOME $PKG"
Sh "cmd package set-home-activity --user 0 $HOME_ACT"
Sh "settings put secure user_setup_complete 1"

Say "home candidates"
Sh 'cmd role get-role-holders --user 0 android.app.role.HOME'

Say "what HOME resolves to"
$resolved = (Sh 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME') -join "`n"
Write-Host $resolved
if ($resolved -notmatch [regex]::Escape($HOME_ACT)) {
    Write-Host "!! HOME does not resolve to $HOME_ACT yet"
}

Say "bringing it up"
Sh 'am start -a android.intent.action.MAIN -c android.intent.category.HOME' | Out-Null
Start-Sleep -Seconds 2
Say "on top now"
Sh 'dumpsys activity activities | grep -m2 -E "mResumedActivity|topResumedActivity"'

Say 'done - press HOME on the remote: it should land on the launcher without asking again'
