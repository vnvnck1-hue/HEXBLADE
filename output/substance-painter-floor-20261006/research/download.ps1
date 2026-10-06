$ErrorActionPreference = 'Stop'
$taskResearchDir = $PSScriptRoot
$taskImageDir = Join-Path $taskResearchDir 'images'
New-Item -ItemType Directory -Path $taskImageDir -Force | Out-Null
$taskImages = @(
    @{file='manzano_01.jpg'; url='https://cdna.artstation.com/p/assets/images/images/013/263/320/large/alberto-angel-manzano-screenshot007.jpg?1538796339'},
    @{file='manzano_02.jpg'; url='https://cdnb.artstation.com/p/assets/images/images/013/263/323/large/alberto-angel-manzano-sss1.jpg?1538796344'},
    @{file='manzano_03.jpg'; url='https://cdna.artstation.com/p/assets/images/images/013/263/324/large/alberto-angel-manzano-sss3.jpg?1538796350'},
    @{file='manzano_04_painter.jpg'; url='https://cdnb.artstation.com/p/assets/images/images/013/263/319/large/alberto-angel-manzano-sbs.jpg?1538796333'}
)
$taskResults = foreach ($taskImage in $taskImages) {
    $taskFile = Join-Path $taskImageDir $taskImage.file
    Invoke-WebRequest -Uri $taskImage.url -OutFile $taskFile -TimeoutSec 30 -UseBasicParsing
    @{file=$taskImage.file; url=$taskImage.url; author='Alberto Angel Manzano'; page='https://manzanoidus.artstation.com/projects/Vdo40g'; sha256=(Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash.ToLower(); bytes=(Get-Item -LiteralPath $taskFile).Length}
}
$taskResults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $taskResearchDir 'images.json') -Encoding UTF8
$taskResults | Select-Object file,bytes | Format-Table
