[CmdletBinding()]
param(
  [string]$PsdkProject = 'C:\Users\Raty\Documents\PSDK\Nuzlocke Graveyard',
  [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PluginName = 'nuzlocke_graveyard'
$RepoRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$PsdkRoot = [System.IO.Path]::GetFullPath($PsdkProject)

$PluginSource = Join-Path $RepoRoot "scripts\$PluginName"
$PluginConfig = Join-Path $PluginSource 'config.yml'
$PsdkLauncher = Join-Path $PsdkRoot 'psdk.bat'
$PsdkScripts = Join-Path $PsdkRoot 'scripts'
$BuildSource = Join-Path $PsdkScripts $PluginName
$BuiltPlugin = Join-Path $PsdkScripts "$PluginName.psdkplug"
$ReleaseDirectory = Join-Path $RepoRoot 'release'
$ReleasePlugin = Join-Path $ReleaseDirectory "$PluginName.psdkplug"

$PluginAssets = @(
  'graphics\interface\nuzlocke_graveyard\frame.png',
  'graphics\interface\nuzlocke_graveyard\button_en.png',
  'graphics\interface\nuzlocke_graveyard\button_fr.png'
)

if (-not (Test-Path -LiteralPath $PluginConfig -PathType Leaf)) {
  throw "Configuration du plugin introuvable : $PluginConfig"
}

if (-not (Test-Path -LiteralPath $PsdkLauncher -PathType Leaf)) {
  throw "Projet PSDK invalide : psdk.bat est introuvable dans $PsdkRoot"
}

foreach ($relativePath in $PluginAssets) {
  $sourcePath = Join-Path $RepoRoot $relativePath
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Asset du plugin introuvable : $sourcePath"
  }
}

$ExpectedBuildSource = [System.IO.Path]::GetFullPath((Join-Path $PsdkScripts $PluginName))
$ActualBuildSource = [System.IO.Path]::GetFullPath($BuildSource)
if ($ActualBuildSource -ne $ExpectedBuildSource) {
  throw "Chemin de préparation inattendu : $ActualBuildSource"
}

Write-Host "Préparation de $PluginName dans le projet PSDK..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $BuildSource) {
  Remove-Item -LiteralPath $BuildSource -Recurse -Force
}
Copy-Item -LiteralPath $PluginSource -Destination $BuildSource -Recurse -Force

foreach ($relativePath in $PluginAssets) {
  $sourcePath = Join-Path $RepoRoot $relativePath
  $destinationPath = Join-Path $PsdkRoot $relativePath
  $destinationDirectory = Split-Path -Parent $destinationPath
  New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
  Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

try {
  if (Test-Path -LiteralPath $BuiltPlugin -PathType Leaf) {
    Remove-Item -LiteralPath $BuiltPlugin -Force
  }

  Write-Host "Compilation du plugin..." -ForegroundColor Cyan
  Push-Location $PsdkRoot
  try {
    & $PsdkLauncher '--util=plugin' 'build' $PluginName
    if ($LASTEXITCODE -ne 0) {
      throw "La compilation PSDK a échoué avec le code $LASTEXITCODE."
    }
  }
  finally {
    Pop-Location
  }

  if (-not (Test-Path -LiteralPath $BuiltPlugin -PathType Leaf)) {
    throw "La compilation n'a pas produit le fichier attendu : $BuiltPlugin"
  }

  New-Item -ItemType Directory -Path $ReleaseDirectory -Force | Out-Null
  Copy-Item -LiteralPath $BuiltPlugin -Destination $ReleasePlugin -Force

  if (-not $SkipInstall) {
    Write-Host "Installation de la version compilée dans le projet de test..." -ForegroundColor Cyan
    Push-Location $PsdkRoot
    try {
      & $PsdkLauncher '--util=plugin' 'load'
      if ($LASTEXITCODE -ne 0) {
        throw "Le rechargement du plugin a échoué avec le code $LASTEXITCODE."
      }
    }
    finally {
      Pop-Location
    }
  }
}
finally {
  if (Test-Path -LiteralPath $BuildSource) {
    Remove-Item -LiteralPath $BuildSource -Recurse -Force
  }
}

$Hash = (Get-FileHash -LiteralPath $ReleasePlugin -Algorithm SHA256).Hash
Write-Host ''
Write-Host 'Build terminé.' -ForegroundColor Green
Write-Host "Plugin : $ReleasePlugin"
Write-Host "SHA-256 : $Hash"
if ($SkipInstall) {
  Write-Host 'Installation dans le projet de test ignorée (-SkipInstall).'
}
else {
  Write-Host "La version compilée est installée dans : $PsdkRoot"
}
