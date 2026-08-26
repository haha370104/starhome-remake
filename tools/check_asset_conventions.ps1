$ErrorActionPreference = "Stop"

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$assetRoot = Join-Path $projectRoot "assets"
$violations = [System.Collections.Generic.List[string]]::new()

$forbiddenPathPatterns = @(
    '(^|[\\/])(pic|pic2|ale)([\\/]|$)',
    '(^|[\\/])chn_\d{4}_\d{2}_\d{2}',
    '(^|[\\/])[0-9a-f]{8}([\\/]|$)',
    '(^|[\\/])(roomsvr\d*|new|final)([_.\\/]|$)',
    '(^|[\\/])(top_btn_|menu_btn_)'
)

foreach ($entry in Get-ChildItem -LiteralPath $assetRoot -Recurse) {
    $relative = $entry.FullName.Substring($assetRoot.Length + 1)
    foreach ($pattern in $forbiddenPathPatterns) {
        if ($relative -match $pattern) {
            $violations.Add("forbidden asset path: $relative")
            break
        }
    }
}

$runtimeFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
    $_.Extension -in '.gd', '.tscn', '.tres', '.json' -and $_.Name -ne 'import_metadata.json'
}
foreach ($file in $runtimeFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($content, 'res://[^"\r\n\]\)]+')) {
        $resourcePath = $match.Value
        foreach ($pattern in $forbiddenPathPatterns) {
            if ($resourcePath -match $pattern) {
                $relative = $file.FullName.Substring($projectRoot.Length + 1)
                $violations.Add("forbidden runtime reference in ${relative}: $resourcePath")
                break
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | Sort-Object -Unique | Write-Error
    exit 1
}

Write-Output "Asset convention check passed."
