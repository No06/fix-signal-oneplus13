$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$sourceRoot = $PSScriptRoot
$outputDirectory = Join-Path $sourceRoot 'dist'
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$outputPath = Join-Path $outputDirectory 'fix-signal-oneplus13-v4.2-temp-root.zip'
$archiveFiles = @(
    'module.prop', 'customize.sh', 'post-fs-data.sh', 'radio-common.sh',
    'recover-radio.sh', 'launch-recovery.sh', 'late-load.sh', 'service.sh',
    'action.sh', 'system.prop', 'sepolicy.rule', 'README.md', 'LICENSE',
    'nvbk/oplusstanvbk.img', 'nvbk/README.txt',
    'META-INF/com/google/android/update-binary',
    'META-INF/com/google/android/updater-script'
)
$utf8 = New-Object Text.UTF8Encoding($false)
$archiveStream = [IO.File]::Open($outputPath, [IO.FileMode]::Create)
$archive = New-Object IO.Compression.ZipArchive($archiveStream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relativePath in $archiveFiles) {
        $fullPath = Join-Path $sourceRoot $relativePath
        $entry = $archive.CreateEntry($relativePath, [IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        try {
            if ($relativePath.EndsWith('.img')) {
                $bytes = [IO.File]::ReadAllBytes($fullPath)
            } else {
                $text = [IO.File]::ReadAllText($fullPath).Replace("`r`n", "`n")
                $bytes = $utf8.GetBytes($text)
            }
            $entryStream.Write($bytes, 0, $bytes.Length)
        } finally { $entryStream.Dispose() }
    }
} finally {
    $archive.Dispose()
    $archiveStream.Dispose()
}
Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath
Write-Output $outputPath
