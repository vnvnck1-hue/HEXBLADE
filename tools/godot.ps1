# Runs this project with the pinned Godot version (godot-version.txt) on any Windows PC.
#
#   tools\godot.ps1 [mode] [godot args...]
#     run     (default) start the game window, return immediately
#     editor  open the editor
#     wait    run the console build in this terminal and return its exit code (tests, bots, captures)
#     setup   only make sure the pinned Godot is installed in .tools\godot
#     which   print the console exe path
#
# Godot lives in <project>\.tools\godot (gitignored). If missing, it is copied from an existing
# install of the exact same version, or downloaded from the official godotengine/godot-builds
# release and checked against the release's SHA512-SUMS.txt. Other versions are never used.
# No param() block on purpose: Godot args such as -s / --path pass through $args untouched.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = Split-Path -Parent $PSScriptRoot
$ver = (Get-Content -LiteralPath (Join-Path $root 'godot-version.txt') -TotalCount 1).Trim()   # e.g. 4.7.2-stable
$expect = $ver -replace '-', '.'                                                              # --version prints 4.7.2.stable.official.<hash>
$dir = Join-Path $root '.tools\godot'
$name = "Godot_v${ver}_win64"
$exe = Join-Path $dir "$name.exe"
$con = Join-Path $dir "${name}_console.exe"

$modes = @('run', 'editor', 'wait', 'setup', 'which')
$mode = 'run'
$rest = @($args)
if ($rest.Count -gt 0 -and $modes -contains [string]$rest[0]) {
	$mode = [string]$rest[0]
	$rest = @($rest | Select-Object -Skip 1)
}

function Fail([string]$msg) {
	Write-Host "[godot] $msg" -ForegroundColor Red
	if ($mode -in @('run', 'editor')) { [void](Read-Host 'Press Enter to close') }
	exit 1
}

function Get-Version([string]$console) {
	if (-not (Test-Path -LiteralPath $console)) { return '' }
	try { return [string](& $console --headless --version 2>$null | Select-Object -Last 1) } catch { return '' }
}

function Test-Pinned { return (Test-Path -LiteralPath $exe) -and (Get-Version $con).StartsWith("$expect.") }

## Another folder that already has both exes of exactly this version (winget, sibling projects, GODOT_HOME)
function Find-LocalCopy {
	$dirs = @()
	if ($env:GODOT_HOME) { $dirs += $env:GODOT_HOME }
	$dirs += Get-ChildItem -LiteralPath (Split-Path -Parent $root) -Directory -ErrorAction SilentlyContinue |
		ForEach-Object { Join-Path $_.FullName '.tools\godot' }
	$wg = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
	if (Test-Path -LiteralPath $wg) {
		$dirs += Get-ChildItem -LiteralPath $wg -Directory -Filter 'GodotEngine.GodotEngine_*' -ErrorAction SilentlyContinue |
			ForEach-Object { $_.FullName; Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
	}
	foreach ($d in $dirs) {
		if ($d -and $d -ne $dir -and (Test-Path -LiteralPath (Join-Path $d "$name.exe")) -and (Get-Version (Join-Path $d "${name}_console.exe")).StartsWith("$expect.")) {
			return $d
		}
	}
	return $null
}

function Install-Pinned {
	New-Item -ItemType Directory -Force -Path $dir | Out-Null
	$src = Find-LocalCopy
	if ($src) {
		Write-Host "[godot] copying Godot $ver from $src"
		Copy-Item -LiteralPath (Join-Path $src "$name.exe"), (Join-Path $src "${name}_console.exe") -Destination $dir -Force
		return
	}
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	$base = "https://github.com/godotengine/godot-builds/releases/download/$ver"
	$zip = Join-Path $dir "$name.exe.zip"
	Write-Host "[godot] downloading Godot $ver (about 70 MB) from $base"
	Invoke-WebRequest -UseBasicParsing -Uri "$base/$name.exe.zip" -OutFile $zip
	$sums = (Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA512-SUMS.txt").Content
	if ($sums -is [byte[]]) { $sums = [Text.Encoding]::ASCII.GetString($sums) }
	$line = ($sums -split "`n") | Where-Object { $_ -match "\s\*?$([regex]::Escape("$name.exe.zip"))\s*$" } | Select-Object -First 1
	if (-not $line) { Remove-Item -LiteralPath $zip -Force; Fail "SHA512-SUMS.txt has no entry for $name.exe.zip" }
	$want = ($line -split '\s+')[0].ToLower()
	$got = (Get-FileHash -LiteralPath $zip -Algorithm SHA512).Hash.ToLower()
	if ($want -ne $got) { Remove-Item -LiteralPath $zip -Force; Fail "checksum mismatch for $name.exe.zip" }
	Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
	Remove-Item -LiteralPath $zip -Force
}

if (-not (Test-Pinned)) {
	try { Install-Pinned } catch { Fail "could not install Godot ${ver}: $($_.Exception.Message)" }
	if (-not (Test-Pinned)) { Fail "Godot in $dir is not $ver (got '$(Get-Version $con)')" }
	Write-Host "[godot] Godot $ver ready in $dir"
}

$q = { param($a) if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }
# Bandicam installs an implicit Vulkan layer (bdcamvk64.dll) that fails to recreate the swapchain on a
# window-mode change: F11 fullscreen froze the game and then crashed (VkResult -2). This variable is the
# layer's own disable switch; it only affects Godot started from here (the editor's play runs inherit it).
$env:VK_LAYER_bandicam_helper_DEBUG_1 = '1'
switch ($mode) {
	'setup' { Write-Host "[godot] $(Get-Version $con)"; exit 0 }
	'which' { Write-Output $con; exit 0 }
	'wait' {
		# Godot writes warnings to stderr; under 'Stop' Windows PowerShell would turn them into terminating errors
		$ErrorActionPreference = 'Continue'
		& $con --path $root @rest
		exit $LASTEXITCODE
	}
	default {
		$list = @()
		if ($mode -eq 'editor') { $list += '--editor' }
		$list += '--path', $root
		$list += $rest
		Start-Process -FilePath $exe -ArgumentList (($list | ForEach-Object { & $q ([string]$_) }) -join ' ')
	}
}
