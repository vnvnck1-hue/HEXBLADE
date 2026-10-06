$ErrorActionPreference = 'Stop'
$researchDir = $PSScriptRoot
$groups = Get-Content -LiteralPath (Join-Path $researchDir 'sources.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$downloadResults = @()
foreach ($group in $groups) {
    $index = 0
    foreach ($url in $group.urls) {
        $index++
        $name = $group.id + '_' + $index.ToString('00') + '.jpg'
        $dest = Join-Path $researchDir ('images/' + $name)
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest -TimeoutSec 30
            $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower()
            $downloadResults += @{group=$group.id;file=('images/'+$name);url=$url;sha256=$hash;status='ok'}
            Write-Output ($name + ' OK')
        } catch {
            $downloadResults += @{group=$group.id;url=$url;status='failed';error=$_.Exception.Message}
            Write-Output ($name + ' FAILED ' + $_.Exception.Message)
        }
    }
}
$downloadResults | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $researchDir 'download_manifest.json') -Encoding UTF8
