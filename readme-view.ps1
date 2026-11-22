function ConvertTo-ReadmeRtfText([string]$text) {
    return [regex]::Replace($text, '[\\{}\x7f-\uffff]', {
        param($match)
        $character = $match.Value[0]
        if ($character -in @('\','{','}')) { return '\' + $character }
        $number = [int]$character
        if ($number -gt 32767) { $number -= 65536 }
        return "\u$($number)?"
    })
}

function ConvertTo-ReadmeRtfLine([string]$line, [hashtable]$links) {
    $text = [Text.StringBuilder]::new()
    $start = 0
    foreach ($match in [regex]::Matches($line, '\[([^\]]+)\]\(([^)]+)\)|\x60([^\x60]+)\x60|\*\*(.+?)\*\*')) {
        [void]$text.Append((ConvertTo-ReadmeRtfText $line.Substring($start, $match.Index - $start)))
        if ($match.Groups[1].Success) {
            $name = $match.Groups[1].Value
            $address = $match.Groups[2].Value
            $uri = [uri]::new([uri]'https://github.com/lomgzhijie/OpenProxySetup/blob/main/', $address)
            $caption = ConvertTo-ReadmeRtfText $name
            if ($uri.Scheme -in @('https','http')) {
                $links[$name] = $uri.AbsoluteUri
                [void]$text.Append('\u57344?{\ul\cf2 ' + $caption + '}\u57345?')
            } else {
                [void]$text.Append($caption)
            }
        } elseif ($match.Groups[3].Success) {
            [void]$text.Append('{\f1\cf2 ' + (ConvertTo-ReadmeRtfText $match.Groups[3].Value) + '}')
        } else {
            [void]$text.Append('{\b ' + (ConvertTo-ReadmeRtfText $match.Groups[4].Value) + '}')
        }
        $start = $match.Index + $match.Length
    }
    [void]$text.Append((ConvertTo-ReadmeRtfText $line.Substring($start)))
    return $text.ToString()
}

function ConvertTo-ReadmeDocument([string[]]$lines, [Drawing.Color]$ink, [Drawing.Color]$accent) {
    $rtf = [Text.StringBuilder]::new()
    $links = @{}
    $headings = [System.Collections.Generic.List[string]]::new()
    $code = $false
    $githubOnly = $false
    $colors = "\red$($ink.R)\green$($ink.G)\blue$($ink.B);\red$($accent.R)\green$($accent.G)\blue$($accent.B);"
    [void]$rtf.Append('{\rtf1\ansi\uc1\deff0{\fonttbl{\f0 Microsoft YaHei UI;}{\f1 Consolas;}}{\colortbl;' + $colors + '}\f0\fs22\cf1 ')

    foreach ($line in $lines) {
        if (!$code -and $line.Trim() -eq '<!-- github-only-start -->') { $githubOnly = $true; continue }
        if ($githubOnly) {
            if ($line.Trim() -eq '<!-- github-only-end -->') { $githubOnly = $false }
            continue
        }
        if ($line.StartsWith('```')) {
            $code = -not $code
            continue
        }
        if ($code) {
            [void]$rtf.Append('\pard\li280\f1\fs20 ' + (ConvertTo-ReadmeRtfText $line) + '\par ')
            continue
        }
        if (!$line.Trim() -or $line.StartsWith('[简体中文](README.md)')) { continue }
        if ($line -match '^(#{1,3})\s+(.+)$') {
            $level = $Matches[1].Length
            $caption = $Matches[2]
            if ($level -gt 1) { $headings.Add($caption) }
            $size = @(0,40,30,25)[$level]
            $content = ConvertTo-ReadmeRtfLine $caption $links
            [void]$rtf.Append("\pard\sb240\sa100\f0\fs$size {\b $content}\par ")
            continue
        }
        if ($line.StartsWith('|')) {
            $cells = $line.Trim().Trim('|').Split('|')
            if ($cells.Count -ge 2 -and $cells[0].Trim() -notmatch '^:?-+:?$') {
                $title = ConvertTo-ReadmeRtfText $cells[0].Trim()
                $content = (@($cells | Select-Object -Skip 1 | ForEach-Object { ConvertTo-ReadmeRtfLine $_.Trim() $links }) -join '\line ')
                [void]$rtf.Append("\pard\li280\sa120\f0\fs22 {\b $title}\line $content\par ")
            }
            continue
        }
        $content = ConvertTo-ReadmeRtfLine ($line -replace '^[-*] ', ([string][char]0x2022 + ' ')) $links
        [void]$rtf.Append("\pard\sa130\f0\fs22 $content\par ")
    }
    [void]$rtf.Append('}')
    return @{ Rtf=$rtf.ToString(); Links=$links; Headings=$headings.ToArray() }
}
