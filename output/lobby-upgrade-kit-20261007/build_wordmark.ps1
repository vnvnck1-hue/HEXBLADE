# Outlined native wordmark: no font needed on the receiving PC.
# Uses installed Arial Black only at build time; keeps all geometry as SVG paths.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$taskLogoFamily = [System.Drawing.FontFamily]::new('Arial Black')
$taskLogoPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
$taskLogoPath.AddString('HEX BLADE', $taskLogoFamily, [int][System.Drawing.FontStyle]::Italic, [single]116, [System.Drawing.PointF]::new(0, 0), [System.Drawing.StringFormat]::GenericTypographic)
$taskLogoBounds = $taskLogoPath.GetBounds()
$taskLogoPts = $taskLogoPath.PathPoints
$taskLogoTypes = $taskLogoPath.PathTypes
$taskLogoCommands = [System.Collections.Generic.List[string]]::new()
function TaskLogoNum([double]$v) { return $v.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }
for ($taskLogoIndex=0; $taskLogoIndex -lt $taskLogoPts.Length; $taskLogoIndex++) {
    $taskLogoType = $taskLogoTypes[$taskLogoIndex] -band 7
    $taskLogoPoint = $taskLogoPts[$taskLogoIndex]
    $taskLogoXY = (TaskLogoNum ($taskLogoPoint.X - $taskLogoBounds.X + 3)) + ' ' + (TaskLogoNum ($taskLogoPoint.Y - $taskLogoBounds.Y + 3))
    if ($taskLogoType -eq 0) { $taskLogoCommands.Add('M' + $taskLogoXY) }
    elseif ($taskLogoType -eq 1) { $taskLogoCommands.Add('L' + $taskLogoXY) }
    elseif ($taskLogoType -eq 3) {
        $taskLogoC = 'C' + $taskLogoXY
        for ($taskLogoCurve=0; $taskLogoCurve -lt 2; $taskLogoCurve++) {
            $taskLogoIndex++
            $taskLogoPoint = $taskLogoPts[$taskLogoIndex]
            $taskLogoC += ' ' + (TaskLogoNum ($taskLogoPoint.X - $taskLogoBounds.X + 3)) + ' ' + (TaskLogoNum ($taskLogoPoint.Y - $taskLogoBounds.Y + 3))
        }
        $taskLogoCommands.Add($taskLogoC)
    }
    if (($taskLogoTypes[$taskLogoIndex] -band 128) -ne 0) { $taskLogoCommands.Add('Z') }
}
$taskLogoWidth = [int][Math]::Ceiling($taskLogoBounds.Width + 6)
$taskLogoHeight = [int][Math]::Ceiling($taskLogoBounds.Height + 6)
$taskLogoSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + $taskLogoWidth + '" height="' + $taskLogoHeight + '" viewBox="0 0 ' + $taskLogoWidth + ' ' + $taskLogoHeight + '"><path fill="#f5eedb" fill-rule="evenodd" d="' + ($taskLogoCommands -join ' ') + '"/></svg>'
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'ui/17_title_wordmark.svg'), $taskLogoSvg + "`n", [System.Text.UTF8Encoding]::new($false))
$taskLogoPath.Dispose()
$taskLogoFamily.Dispose()
Write-Output "outlined_wordmark=$taskLogoWidth x $taskLogoHeight"
