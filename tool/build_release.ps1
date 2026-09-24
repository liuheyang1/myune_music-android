$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$signing = Join-Path $projectRoot 'android/key.properties'
$privateSigning = Join-Path (Split-Path -Parent $projectRoot) 'myune_music-android-signing/key.properties'
$originalSigningEnvironment = $env:MYUNE_SIGNING_PROPERTIES
if (-not $env:MYUNE_SIGNING_PROPERTIES -and (Test-Path -LiteralPath $privateSigning)) {
    $env:MYUNE_SIGNING_PROPERTIES = $privateSigning
}
if (-not (Test-Path -LiteralPath $signing) -and
    (-not $env:MYUNE_SIGNING_PROPERTIES -or
     -not (Test-Path -LiteralPath $env:MYUNE_SIGNING_PROPERTIES))) {
    throw 'Provide MYUNE_SIGNING_PROPERTIES or create android/key.properties before building a public APK.'
}

Push-Location $projectRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & flutter test test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & flutter build apk --release --target-platform android-arm64 --split-per-abi
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
    $checksum = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
    Write-Output "APK: $apk"
    Write-Output "SHA-256: $checksum"
} finally {
    Pop-Location
    $env:MYUNE_SIGNING_PROPERTIES = $originalSigningEnvironment
}
