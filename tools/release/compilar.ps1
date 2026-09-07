# Compila el APK con TODOS los motores y comprueba que de verdad quedaron dentro.
#
# Existe porque `flutter build apk --release` a secas compila sin servidores y
# el resultado no se distingue de uno bueno: el APK se instala, arranca y
# funciona, solo que en Ajustes aparecen dos motores en vez de cinco. Es un
# fallo silencioso, y por eso hace falta comprobarlo en vez de confiar.
#
#   .\tools\release\compilar.ps1                 # perfil pedro, todos los motores
#   .\tools\release\compilar.ps1 -Perfil amigo   # compilación de un probador
#   .\tools\release\compilar.ps1 -Limpio         # obligatorio si cambió la versión
#   .\tools\release\compilar.ps1 -Instalar       # y lo deja en el teléfono
#
# Ver README.md de esta carpeta para qué lleva cada .json y por qué.

[CmdletBinding()]
param(
    [string]$Perfil = "pedro",
    [switch]$Limpio,
    [switch]$Instalar
)

$ErrorActionPreference = "Stop"
$raiz = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $raiz

# El .json personal lleva TTS_TOKEN y, si se quiere, PIPER_URL: no está en git.
# Los otros dos sí, así que valen para cualquier compilación.
$personal = "tools/release/$Perfil.json"
if (-not (Test-Path $personal)) {
    Write-Error "No existe $personal. Copiá tools/release/tester.example.json y editalo (ver README.md)."
}
$configs = @($personal)
foreach ($extra in @("tools/release/kokoro.json", "tools/release/f5.json")) {
    if (Test-Path $extra) { $configs += $extra }
    else { Write-Warning "Falta ${extra}: ese motor no va a estar en el APK." }
}

# Las URLs que esperamos encontrar después dentro del binario. Se leen de los
# mismos .json que se le pasan al build, así que un archivo incompleto -- el
# fallo que el README avisa que no da la cara -- se detecta abajo.
$esperados = @{}
foreach ($c in $configs) {
    $json = Get-Content $c -Raw | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) {
        if ($p.Name -like "*_URL" -and $p.Value) { $esperados[$p.Name] = $p.Value }
    }
}

Write-Host "Perfil:  $Perfil"
Write-Host "Config:  $($configs -join ', ')"
Write-Host "Motores: Edge y Teléfono (siempre) + $($esperados.Keys -join ', ')"
Write-Host ""

# `flutter build apk` no regenera el manifiesto cuando lo único que cambió es la
# versión: Gradle no vigila android/local.properties como entrada de tarea, y el
# APK sale con el versionName viejo dentro. Ver README.md, "Al subir la versión".
if ($Limpio) { flutter clean; if ($LASTEXITCODE -ne 0) { Write-Error "flutter clean falló." } }

$argumentos = @("build", "apk", "--release")
foreach ($c in $configs) { $argumentos += "--dart-define-from-file=$c" }
& flutter @argumentos
if ($LASTEXITCODE -ne 0) { Write-Error "El build falló." }

# --- Comprobación: los valores compilados están en el snapshot de Dart ---
#
# String.fromEnvironment deja el valor como cadena literal dentro de libapp.so
# (ver README.md, "Lo que un APK no puede esconder"). Eso, que es lo que impide
# tratar el token como secreto, sirve aquí para verificar el build.
$apk = "build/app/outputs/flutter-apk/app-release.apk"
if (-not (Test-Path $apk)) { Write-Error "No apareció $apk." }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $apk))
try {
    $so = $zip.Entries | Where-Object { $_.FullName -like "lib/*/libapp.so" } | Select-Object -First 1
    if (-not $so) { Write-Error "El APK no trae libapp.so: no se puede comprobar nada." }

    $flujo = $so.Open()
    $memoria = New-Object IO.MemoryStream
    $flujo.CopyTo($memoria)
    $flujo.Close()
    # Latin1 mapea byte a carácter, así que la búsqueda no depende de decodificar
    # el binario como texto válido.
    $contenido = [Text.Encoding]::Latin1.GetString($memoria.ToArray())
    $memoria.Dispose()
} finally {
    $zip.Dispose()
}

Write-Host ""
$faltan = @()
foreach ($nombre in $esperados.Keys | Sort-Object) {
    if ($contenido.Contains($esperados[$nombre])) {
        Write-Host "  OK       $nombre"
    } else {
        Write-Host "  FALTA    $nombre" -ForegroundColor Red
        $faltan += $nombre
    }
}
if ($faltan.Count -gt 0) {
    Write-Error "El APK se compiló sin $($faltan -join ', '): esos motores no aparecerán en Ajustes. No lo repartas."
}

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Split('+')[0].Trim()
Write-Host ""
Write-Host "APK correcto: $apk ($version, perfil $Perfil)"

if ($Instalar) {
    adb install -r $apk
    if ($LASTEXITCODE -ne 0) { Write-Error "adb install falló." }
    # Lo que dice el APK por dentro, no lo que dice el nombre del archivo.
    adb shell dumpsys package com.pedrosolorzano.voicex_movil | Select-String versionName
}
