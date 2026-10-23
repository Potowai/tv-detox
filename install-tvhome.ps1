# Installs the rebuilt tvhome on the TV once it is reachable over ADB.
#
#   powershell -ExecutionPolicy Bypass -File install-tvhome.ps1 -Ip 192.168.1.50
#
# The build is signed with a key of its own, so Android refuses to update the old
# com.ansub.tvhome over it: this uninstalls the old launcher, installs the new one,
# clears the saved row (our build then fills it from the apps actually installed)
# and makes it the home screen again.
param(
    [string]$Ip = '192.168.1.50',
    [switch]$KeepRow
)
$ErrorActionPreference = 'Stop'
$adb = 'adb'
$apk = Join-Path $PSScriptRoot 'out\tvhome.apk'
if (-not (Test-Path $apk)) { throw "no build yet: run build.ps1 first ($apk)" }

function Say($m) { Write-Host "== $m" }
# adb writes its warnings ("Activity not started") to stderr; with
# $ErrorActionPreference = 'Stop' PowerShell would turn those into fatal errors.
function Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Argv)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { (& $adb @Argv 2>&1) } finally { $ErrorActionPreference = $prev }
}
function Sh([string]$cmd) { Adb @('-s', "$Ip`:5555", 'shell', $cmd) }

Say "connecting to $Ip`:5555"
& $adb connect "$Ip`:5555" | Out-Null
Start-Sleep -Milliseconds 800
$state = (& $adb devices) | Where-Object { $_ -like "$Ip`:5555*" }
if (-not $state) { throw "no ADB answer from $Ip - is the TV on, with ADB debugging on?" }
if ($state -match 'unauthorized') { throw "ADB is unauthorized: accept 'Allow USB debugging' on the TV and rerun" }
if ($state -notmatch '\bdevice\b') { throw "ADB is not ready on $($Ip): $state" }
Say "device state: $state"

Say "old launcher version"
Sh 'dumpsys package com.ansub.tvhome | grep -m1 versionName'

Say "uninstalling the old launcher (its signing key cannot be reused)"
Sh 'pm uninstall com.ansub.tvhome'

Say "installing $apk"
& $adb -s "$Ip`:5555" install -r $apk

if (-not $KeepRow) {
    Say "clearing the saved row so it rebuilds from the installed apps"
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Sh "am start -n com.ansub.tvhome/.MainActivity --es stamp $stamp --es apps auto" | Out-Null
}

Say "making it the home screen"
Sh 'cmd role add-role-holder --user 0 android.app.role.HOME com.ansub.tvhome'
Sh 'cmd package set-home-activity --user 0 com.ansub.tvhome/.MainActivity'
Sh 'am start -a android.intent.action.MAIN -c android.intent.category.HOME' | Out-Null

Start-Sleep -Seconds 2
Say "what is on top now"
Sh 'dumpsys activity activities | grep -m2 -E "mResumedActivity|topResumedActivity"'
Say "version installed"
Sh 'dumpsys package com.ansub.tvhome | grep -m1 versionName'
Say 'done - press HOME on the remote and check the row'
