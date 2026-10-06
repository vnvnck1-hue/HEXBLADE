# Runs the pinned Blender version (blender-version.txt) on any Windows PC.
#
#   tools\blender.ps1 [mode] [blender args...]
#     run     (default) open the Blender window, return immediately
#     wait    run Blender in this terminal (background scripts, exports, renders) and return its exit code
#     model   build one model script: tools\blender.ps1 model models\src\<name>.py [--no-preview] [--no-export]
#     live    open the Blender window with the live bridge (tools\blender\live.py) [file.blend]
#     send    run a .py inside the open live window and print its output: tools\blender.ps1 send code.py [seconds]
#     setup   only make sure the pinned Blender is installed in .tools\blender
#     which   print the blender.exe path
#
# Blender lives in <project>\.tools\blender (gitignored). If missing, it is copied from an existing
# install of the exact same version (BLENDER_HOME, a sibling project's .tools\blender), or downloaded as the
# portable zip from download.blender.org and checked against the release's .sha256 file.
# Other versions are never used. No param() block on purpose: Blender args pass through $args untouched.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot
$ver = (Get-Content -LiteralPath (Join-Path $root 'blender-version.txt') -TotalCount 1).Trim()   # e.g. 5.2.2
$series = ($ver -split '\.')[0..1] -join '.'                                                    # e.g. 5.2
$dir = Join-Path $root '.tools\blender'
$name = "blender-$ver-windows-x64"
$exe = Join-Path $dir "$name\blender.exe"

$modes = @('run', 'wait', 'model', 'live', 'send', 'setup', 'which')
$mode = 'run'
$rest = @($args)
if ($rest.Count -gt 0 -and $modes -contains [string]$rest[0]) {
	$mode = [string]$rest[0]
	$rest = @($rest | Select-Object -Skip 1)
}

function Fail([string]$msg) {
	Write-Host "[blender] $msg" -ForegroundColor Red
	if ($mode -in @('run', 'live')) { [void](Read-Host 'Press Enter to close') }
	exit 1
}

function Get-Version([string]$path) {
	if (-not (Test-Path -LiteralPath $path)) { return '' }
	try {
		$ErrorActionPreference = 'Continue'
		return [string](& $path --factory-startup -b --version 2>$null | Where-Object { $_ -match '^Blender ' } | Select-Object -First 1)
	} catch { return '' }
}

function Test-Pinned { return (Get-Version $exe) -match "^Blender $([regex]::Escape($ver))(\s|$)" }

function Find-LocalCopy {
	$dirs = @()
	if ($env:BLENDER_HOME) { $dirs += $env:BLENDER_HOME }
	$dirs += Get-ChildItem -LiteralPath (Split-Path -Parent $root) -Directory -ErrorAction SilentlyContinue |
		ForEach-Object { Join-Path $_.FullName ".tools\blender\$name" }
	foreach ($d in $dirs) {
		$e = Join-Path $d 'blender.exe'
		if ($d -and $d -ne (Join-Path $dir $name) -and ((Get-Version $e) -match "^Blender $([regex]::Escape($ver))(\s|$)")) { return $d }
	}
	return $null
}

function Install-Pinned {
	New-Item -ItemType Directory -Force -Path $dir | Out-Null
	$src = Find-LocalCopy
	if ($src) {
		Write-Host "[blender] copying Blender $ver from $src"
		Copy-Item -LiteralPath $src -Destination (Join-Path $dir $name) -Recurse -Force
		return
	}
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$base = "https://download.blender.org/release/Blender$series"
	$zip = Join-Path $dir "$name.zip"
	Write-Host "[blender] downloading Blender $ver (about 400 MB) from $base"
	Invoke-WebRequest -UseBasicParsing -Uri "$base/$name.zip" -OutFile $zip
	$sums = (Invoke-WebRequest -UseBasicParsing -Uri "$base/blender-$ver.sha256").Content
	if ($sums -is [byte[]]) { $sums = [Text.Encoding]::ASCII.GetString($sums) }
	$line = ($sums -split "`n") | Where-Object { $_ -match "\s\*?$([regex]::Escape("$name.zip"))\s*$" } | Select-Object -First 1
	if (-not $line) { Remove-Item -LiteralPath $zip -Force; Fail "blender-$ver.sha256 has no entry for $name.zip" }
	$want = ($line -split '\s+')[0].ToLower()
	$got = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
	if ($want -ne $got) { Remove-Item -LiteralPath $zip -Force; Fail "checksum mismatch for $name.zip" }
	Write-Host '[blender] extracting...'
	# tar (bsdtar, built into Windows 10+) is much faster than Expand-Archive on a 400 MB zip
	$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
	if (Test-Path -LiteralPath $tar) { & $tar -xf $zip -C $dir; if ($LASTEXITCODE -ne 0) { Fail 'tar failed to extract the zip' } }
	else { Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force }
	Remove-Item -LiteralPath $zip -Force
}

if (-not (Test-Pinned)) {
	try { Install-Pinned } catch { Fail "could not install Blender ${ver}: $($_.Exception.Message)" }
	if (-not (Test-Pinned)) { Fail "Blender in $dir is not $ver (got '$(Get-Version $exe)')" }
	Write-Host "[blender] Blender $ver ready in $dir"
}

$q = { param($a) if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
switch ($mode) {
	'setup' { Write-Host "[blender] $(Get-Version $exe)"; exit 0 }
	'which' { Write-Output $exe; exit 0 }
	'wait' {
		$ErrorActionPreference = 'Continue'
		& $exe @rest
		exit $LASTEXITCODE
	}
	'model' {
		# Build a model script headless: export .glb into assets\models and render previews into output\models
		$ErrorActionPreference = 'Continue'
		& $exe --factory-startup -b --python-exit-code 1 --python (Join-Path $root 'tools\blender\build.py') -- @rest
		exit $LASTEXITCODE
	}
	'live' {
		$list = @('--python', (Join-Path $root 'tools\blender\live.py')) + $rest
		Start-Process -FilePath $exe -ArgumentList (($list | ForEach-Object { & $q ([string]$_) }) -join ' ')
	}
	'send' {
		# Drop the code into the live window's inbox and wait for its outbox report
		$box = Join-Path $root '.tools\blender_live'
		$alive = Join-Path $box 'alive.txt'
		$livePid = if (Test-Path -LiteralPath $alive) { [int](Get-Content -LiteralPath $alive -TotalCount 1) } else { 0 }
		if (-not $livePid -or -not (Get-Process -Id $livePid -ErrorAction SilentlyContinue)) { Fail 'no live Blender window: start it with tools\blender.ps1 live (or launchers\dev\blender_live.cmd)' }
		if ($rest.Count -lt 1 -or -not (Test-Path -LiteralPath $rest[0])) { Fail 'usage: tools\blender.ps1 send <code.py> [seconds]' }
		$limit = if ($rest.Count -gt 1) { [double]$rest[1] } else { 120 }
		$job = 'job_' + [DateTime]::Now.ToString('HHmmss_fff')
		$out = Join-Path $box "outbox\$job.txt"
		$tmp = Join-Path $box "inbox\$job.tmp"
		Copy-Item -LiteralPath $rest[0] -Destination $tmp
		Move-Item -LiteralPath $tmp -Destination (Join-Path $box "inbox\$job.py")
		$t0 = [DateTime]::Now
		while (-not (Test-Path -LiteralPath $out)) {
			if (([DateTime]::Now - $t0).TotalSeconds -gt $limit) { Fail "no reply from the live window after $limit s ($job)" }
			Start-Sleep -Milliseconds 200
		}
		$text = Get-Content -LiteralPath $out -Encoding UTF8
		Remove-Item -LiteralPath $out -Force
		$text | Select-Object -Skip 1 | ForEach-Object { Write-Output $_ }
		if ($text[0] -ne 'OK') { Write-Host '[blender] live code raised an error' -ForegroundColor Red; exit 1 }
		exit 0
	}
	default {
		Start-Process -FilePath $exe -ArgumentList (($rest | ForEach-Object { & $q ([string]$_) }) -join ' ')
	}
}
