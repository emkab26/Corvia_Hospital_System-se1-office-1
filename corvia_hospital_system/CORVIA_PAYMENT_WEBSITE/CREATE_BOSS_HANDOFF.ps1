param(
  [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'CORVIA_PAYMENT_WEBSITE_HANDOFF')
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$expectedRoot = [System.IO.Path]::GetFullPath($repositoryRoot)
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)

if (-not $resolvedOutput.StartsWith($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'The handoff output must stay inside the Corvia repository.'
}

if (Test-Path -LiteralPath $resolvedOutput) {
  throw "Output already exists: $resolvedOutput. Rename or remove it deliberately before rebuilding."
}

$websiteOutput = Join-Path $resolvedOutput 'website'
$migrationOutput = Join-Path $resolvedOutput 'supabase\migrations'
$functionsOutput = Join-Path $resolvedOutput 'supabase\functions'

New-Item -ItemType Directory -Path $websiteOutput, $migrationOutput, $functionsOutput | Out-Null

$websiteFiles = @(
  '.env.example',
  'SERVER.env.example',
  '.gitignore',
  'BOSS_HOSTING_HANDOFF.md',
  'Caddyfile.example',
  'compose.yaml',
  'Dockerfile',
  'package-lock.json',
  'package.json',
  'README.md'
)

foreach ($file in $websiteFiles) {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $websiteOutput
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'public') -Destination $websiteOutput -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src') -Destination $websiteOutput -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test') -Destination $websiteOutput -Recurse

$migrationNames = @(
  '20261006_corvia_payfast_portal.sql',
  '20261009_corvia_payment_escalation.sql'
)

foreach ($migration in $migrationNames) {
  Copy-Item -LiteralPath (Join-Path $repositoryRoot "supabase\migrations\$migration") -Destination $migrationOutput
}

foreach ($functionName in @('create-payment', 'payment-review')) {
  $functionDestination = Join-Path $functionsOutput $functionName
  New-Item -ItemType Directory -Path $functionDestination | Out-Null
  Copy-Item -LiteralPath (Join-Path $repositoryRoot "supabase\functions\$functionName\index.ts") -Destination $functionDestination
}

$zipPath = "$resolvedOutput.zip"
Compress-Archive -Path (Join-Path $resolvedOutput '*') -DestinationPath $zipPath -CompressionLevel Optimal

Write-Output "Handoff folder: $resolvedOutput"
Write-Output "Handoff ZIP:    $zipPath"
