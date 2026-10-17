$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustRoot = Join-Path $projectRoot 'rust'
$rustOutput = "\\?\" + (Join-Path $rustRoot 'src\frb_generated.rs')
$generator = (Get-Command flutter_rust_bridge_codegen -ErrorAction Stop).Source

Push-Location $projectRoot
try {
    & $generator generate `
        --rust-input 'crate::api' `
        --rust-root $rustRoot `
        --rust-output $rustOutput `
        --dart-output 'lib\src\rust'
    if ($LASTEXITCODE -ne 0) {
        throw "flutter_rust_bridge code generation failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
