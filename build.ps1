# Builds out\tvhome.apk on Windows without the Android SDK manager.
# Mirrors build.sh: aapt2 + javac + d8 + zipalign + apksigner.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$SDK = $env:ANDROID_SDK
if (-not $SDK) { $SDK = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$BT  = Join-Path $SDK 'build-tools\36.1'
$JAR = Join-Path $SDK 'platforms\android-34\android.jar'
$JAVA = $env:JAVA_HOME
if (-not $JAVA) { throw 'set JAVA_HOME to a JDK 21 (d8 in build-tools 34.0.0 cannot read JDK 21 classes)' }
$env:JAVA_HOME = $JAVA
$env:PATH = "$JAVA\bin;$env:PATH"

if (-not (Test-Path $JAR)) { throw "android.jar missing: $JAR" }
if (-not (Test-Path (Join-Path $BT 'aapt2.exe'))) { throw "build-tools missing: $BT" }

if (Test-Path out) { Remove-Item out -Recurse -Force }
New-Item -ItemType Directory -Force -Path out\classes, out\dex, out\gen\com\ansub\tvhome | Out-Null

# --- Apps.java from apps.txt -------------------------------------------------
$pkgs = Get-Content apps.txt |
    Where-Object { $_ -notmatch '^\s*#' } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('package com.ansub.tvhome;')
[void]$sb.AppendLine('final class Apps { static final String[] LIST = {')
foreach ($p in $pkgs) { [void]$sb.AppendLine("    `"$p`",") }
[void]$sb.AppendLine('}; }')
[IO.File]::WriteAllText((Join-Path $PWD 'out\gen\com\ansub\tvhome\Apps.java'), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

# --- resources + manifest ----------------------------------------------------
& "$BT\aapt2.exe" link -o out\base.apk -I $JAR --manifest AndroidManifest.xml --min-sdk-version 21 --target-sdk-version 34 -A assets
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed ($LASTEXITCODE)" }

# --- javac -------------------------------------------------------------------
$srcs = @(Get-ChildItem src, out\gen -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$common = @('-nowarn', '-Xlint:-options', '-encoding', 'UTF-8', '-source', '1.8', '-target', '1.8', '-d', 'out\classes')
& "$JAVA\bin\javac.exe" @common -bootclasspath "$JAR;$BT\core-lambda-stubs.jar" @srcs
if ($LASTEXITCODE -ne 0) {
    Write-Host 'bootclasspath rejected, retrying with -classpath'
    $common2 = @('-nowarn', '-Xlint:-options', '-encoding', 'UTF-8', '-source', '1.8', '-target', '1.8', '-d', 'out\classes', '-classpath', "$JAR;$BT\core-lambda-stubs.jar")
    & "$JAVA\bin\javac.exe" @common2 @srcs
    if ($LASTEXITCODE -ne 0) { throw "javac failed ($LASTEXITCODE)" }
}

# --- dex ---------------------------------------------------------------------
$classes = @(Get-ChildItem out\classes -Recurse -Filter *.class | ForEach-Object { $_.FullName })
& "$BT\d8.bat" --min-api 21 --release --lib $JAR --output out\dex @classes
if ($LASTEXITCODE -ne 0) { throw "d8 failed ($LASTEXITCODE)" }
if (-not (Test-Path out\dex\classes.dex)) { throw 'd8 produced no classes.dex' }

# --- classes.dex into the apk (no zip.exe on Windows) ------------------------
Copy-Item out\base.apk out\unsigned.apk -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open((Join-Path $PWD 'out\unsigned.apk'), 'Update')
try {
    $old = $zip.GetEntry('classes.dex')
    if ($old) { $old.Delete() }
    $entry = $zip.CreateEntry('classes.dex', [IO.Compression.CompressionLevel]::Optimal)
    $dst = $entry.Open()
    $src = [IO.File]::OpenRead((Join-Path $PWD 'out\dex\classes.dex'))
    $src.CopyTo($dst)
    $src.Dispose(); $dst.Dispose()
} finally { $zip.Dispose() }

# --- align + sign ------------------------------------------------------------
& "$BT\zipalign.exe" -f 4 out\unsigned.apk out\aligned.apk
if ($LASTEXITCODE -ne 0) { throw "zipalign failed ($LASTEXITCODE)" }

$KS = $env:TVHOME_KEYSTORE; if (-not $KS) { $KS = 'key.jks' }; $PASS = $env:TVHOME_KEY_PASS; if (-not $PASS) { $PASS = 'tvhome123' }
if (-not (Test-Path $KS)) {
    & "$JAVA\bin\keytool.exe" -genkeypair -keystore $KS -storepass $PASS -keypass $PASS -alias tvhome `
        -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=tvhome' | Out-Null
}
& "$BT\apksigner.bat" sign --ks $KS --ks-pass "pass:$PASS" --out out\tvhome.apk out\aligned.apk
if ($LASTEXITCODE -ne 0) { throw "apksigner failed ($LASTEXITCODE)" }

& "$BT\apksigner.bat" verify --print-certs out\tvhome.apk | Select-Object -First 3
Get-Item out\tvhome.apk | ForEach-Object { "Built {0}  {1:N0} bytes" -f $_.FullName, $_.Length }
