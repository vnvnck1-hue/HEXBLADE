$ErrorActionPreference = 'Stop'
$researchDir = $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $researchDir 'pages') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $researchDir 'images') | Out-Null
$researchSources = @(
    @{ id='01_tinker'; title='Hearthstone Battlegrounds Tinker Tavern Board'; artist='Tiffany Chiu'; url='https://tiffachiu.artstation.com/projects/8wAA0O' },
    @{ id='02_box'; title='Hearthstone The Box'; artist='Ben Thompson'; url='https://benthompsonart.artstation.com/projects/d88Ro1' },
    @{ id='03_scholomance'; title='Hearthstone Scholomance Academy Board'; artist='Jay Axer'; url='https://jayaxer.artstation.com/projects/3dq2D2' },
    @{ id='04_nathria'; title='Murder at Castle Nathria Environment Concepts'; artist='Christopher Hayes'; url='https://craze.artstation.com/projects/r91NJL' },
    @{ id='05_classrooms'; title='Scholomance Academy'; artist='Luke Mancini'; url='https://mrjackart.artstation.com/projects/L3Qo9r' },
    @{ id='06_vault'; title='World of Warcraft Adamant Vaults'; artist='Patrick Burke'; url='https://patrickburke.artstation.com/projects/8wnE9x' },
    @{ id='07_bastion'; title='World of Warcraft Bastion Environment'; artist='Kelli Hoover'; url='https://teddybeartoast.artstation.com/projects/w6qrvV' },
    @{ id='08_nathria_3d'; title='Murder at Castle Nathria Board'; artist='Robin Dao'; url='https://robindao.artstation.com/projects/9Eb1WQ' }
)
$records = @()
foreach ($entry in $researchSources) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $entry.url
        $html = $response.Content
        [IO.File]::WriteAllText((Join-Path $researchDir ('pages/' + $entry.id + '.html')), $html)
        $normalized = $html.Replace('\/', '/').Replace('&amp;', '&')
        $urls = @([regex]::Matches($normalized, 'https://(?:cdna|cdnb|cdnc|cdn|cdna2)\.artstation\.com/p/assets/images/images/[^"''<>\s]+') | ForEach-Object { $_.Value } | Select-Object -Unique)
        $record = @{id=$entry.id; title=$entry.title; artist=$entry.artist; page_url=$entry.url; image_urls=$urls; status='ok'}
        $records += $record
        Write-Output ($entry.id + ' images=' + $urls.Count)
        $urls | Select-Object -First 6 | Write-Output
    } catch {
        $records += @{id=$entry.id; page_url=$entry.url; status='failed'; error=$_.Exception.Message}
        Write-Output ($entry.id + ' FAILED ' + $_.Exception.Message)
    }
}
$records | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $researchDir 'pages_manifest.json')
