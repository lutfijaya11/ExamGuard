$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$jdkCandidates = @(
    "C:\Program Files\Android\Android Studio2\jbr",
    "C:\Program Files\Android\Android Studio1\jbr",
    "C:\Program Files\Android\Android Studio\jbr"
)

foreach ($cand in $jdkCandidates) {
    $javaExe = Join-Path $cand "bin\java.exe"
    if (Test-Path $javaExe) {
        $verOut = cmd /c "`"$javaExe`" -version 2>&1"
        if ($verOut -match '"(17|21)\.') {
            $env:JAVA_HOME = $cand
            $env:PATH = "$cand\bin;$env:PATH"
            Write-Host "Menggunakan JDK kompatibel: $cand"
            break
        }
    }
}

Push-Location $root
try {
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze gagal" }

    flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test gagal" }

    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk gagal" }

    Write-Host "`nAPK siap di: $(Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk')"
}
finally {
    Pop-Location
}
