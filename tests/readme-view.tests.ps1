$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot '../readme-view.ps1')
$document = ConvertTo-ReadmeDocument @(
    '<!-- github-only-start -->', '<div>GITHUB_ONLY_SENTINEL</div>',
    '<!-- github-only-end -->', '# Documentation', '| Item | Windows | Android |',
    '|---|---|---|', '| Platform | desktop-value | phone-value |'
) ([Drawing.Color]::Black) ([Drawing.Color]::Blue)
if ($document.Rtf.Contains('GITHUB_ONLY_SENTINEL') -or !$document.Rtf.Contains('desktop-value') -or !$document.Rtf.Contains('phone-value')) {
    throw 'GitHub-only filtering or three-column rendering failed'
}
foreach ($name in @('README.md','README.en.md','README.ja.md','README.ko.md')) {
    $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../$name") -Encoding UTF8
    $document = ConvertTo-ReadmeDocument $source ([Drawing.Color]::Black) ([Drawing.Color]::Blue)
    if ($document.Rtf -match '<div|<img|github-only-|&nbsp;' -or !$document.Rtf.Contains('Android')) {
        throw "Embedded document contains presentation markup or loses platform content: $name"
    }
}
'PASS GitHub-only filtering and multi-column offline documentation in four languages'
