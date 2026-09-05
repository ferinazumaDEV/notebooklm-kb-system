<#
.SYNOPSIS
    One-shot Windows installer for the NotebookLM KB System.

.DESCRIPTION
    Automates the manual flow in install/windows-powershell.md:

      1. Finds a suitable Python (3.10+; 3.11+ recommended).
      2. Creates an isolated virtualenv under the KB root (default: $HOME\.kb\venv).
      3. Installs the CLI with its browser extras:  pip install "notebooklm-py[browser,cookies]".
      4. DETECTS which browser you have (Chrome / Edge / Brave / Firefox) via the
         registry App Paths and the usual Program Files locations, and chooses the
         right login flag:
             Chrome / Edge      -> notebooklm login --browser chrome|msedge
             Brave / Firefox    -> notebooklm login --browser-cookies brave|firefox
             none of the above  -> playwright install chromium, then --browser chromium
      5. Runs notebooklm login to seed the reusable session profile.
      6. Verifies auth with a real, non-destructive call (notebooklm list).
      7. Prints the next steps (create a notebook, add a source, run research).

    The script never activates the venv (which would trip PowerShell's execution
    policy). It calls the venv's python.exe / notebooklm.exe / playwright.exe by
    full path instead, so it works under any execution policy.

.PARAMETER KbRoot
    Where the KB lives. The venv is created at <KbRoot>\venv. Default: $HOME\.kb.

.PARAMETER Browser
    Force a browser instead of auto-detecting. One of:
    chrome, msedge, chromium, brave, firefox. Default: auto.

.PARAMETER SkipLogin
    Do everything except the interactive login + verify (useful for CI or when you
    will copy an existing session profile in by hand).

.PARAMETER Recreate
    Delete and rebuild the venv even if one already exists.

.PARAMETER EnableHeadlessReauth
    Persist NOTEBOOKLM_HEADLESS_REAUTH=1 as a user environment variable so long or
    scheduled runs (deep research) can refresh their own session mid-run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install\install.ps1
    Full auto install: detect the browser, install, log in, verify.

.EXAMPLE
    .\install\install.ps1 -Browser msedge -EnableHeadlessReauth
    Force Edge for login and persist headless re-auth for scheduled runs.

.EXAMPLE
    .\install\install.ps1 -SkipLogin
    Install only; you will log in (or copy a session profile) yourself later.

.NOTES
    Copyright (C) 2026 Fernando Aporta Franco — Licensed under AGPL-3.0 (see LICENSE).
    Free software with ABSOLUTELY NO WARRANTY; redistribute under the AGPL-3.0 terms.

    Part of the NotebookLM KB System. Placeholders only — no private data.
    See install/windows-powershell.md for the manual, step-by-step version.
#>

[CmdletBinding()]
param(
    [string]$KbRoot = (Join-Path $HOME '.kb'),

    [ValidateSet('auto', 'chrome', 'msedge', 'chromium', 'brave', 'firefox')]
    [string]$Browser = 'auto',

    [switch]$SkipLogin,
    [switch]$Recreate,
    [switch]$EnableHeadlessReauth
)

# ---------------------------------------------------------------------------
# Robustness: stop on the first error, and treat unset variables / bad property
# accesses as errors so typos surface immediately instead of silently passing.
# ---------------------------------------------------------------------------
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Small output helpers so the log reads clearly.
# ---------------------------------------------------------------------------
function Write-Step { param([string]$Msg) Write-Host ""; Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Info { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Gray }
function Write-Ok   { param([string]$Msg) Write-Host "    OK  $Msg" -ForegroundColor Green }
function Write-Warn2{ param([string]$Msg) Write-Host "    !!  $Msg" -ForegroundColor Yellow }

# Join a path only when the base is set — some env vars can be null on odd setups,
# and Join-Path with a null base throws under $ErrorActionPreference='Stop'.
function Join-IfBase {
    param([string]$Base, [string]$Rest)
    if ($Base) { return (Join-Path $Base $Rest) }
    return $null
}

# ---------------------------------------------------------------------------
# Invoke-Native: run a native executable and throw on a non-zero exit code.
# PowerShell's $ErrorActionPreference does NOT catch native exit codes on its
# own, so we check $LASTEXITCODE explicitly. Output streams straight to the
# console (needed for the interactive login window).
# ---------------------------------------------------------------------------
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [string[]]$Arguments = @(),
        [string]$What = ''
    )
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        $label = if ($What) { $What } else { "$Exe $($Arguments -join ' ')" }
        throw "Command failed (exit $LASTEXITCODE): $label"
    }
}

# ---------------------------------------------------------------------------
# Read the (default) value of an "App Paths" registry key — Windows records the
# full exe path for installed apps here, per-machine (HKLM) and per-user (HKCU).
# Returns the path if it exists on disk, else $null.
# ---------------------------------------------------------------------------
function Get-AppPathExe {
    param([Parameter(Mandatory)][string]$ExeName)
    foreach ($hive in 'HKLM:', 'HKCU:') {
        $key = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName"
        if (Test-Path $key) {
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            # Under StrictMode, guard the property access — the key may lack a default value.
            if ($props -and ($props.PSObject.Properties.Name -contains '(default)')) {
                $val = $props.'(default)'
                if ($val) {
                    $val = $val.Trim('"')
                    if (Test-Path $val) { return $val }
                }
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Find a browser by its App Paths registry entry OR a list of candidate paths.
# Returns the resolved exe path, or $null if not installed.
# ---------------------------------------------------------------------------
function Find-Browser {
    param(
        [Parameter(Mandatory)][string]$ExeName,
        [string[]]$Candidates = @()
    )
    $fromReg = Get-AppPathExe -ExeName $ExeName
    if ($fromReg) { return $fromReg }
    foreach ($p in $Candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Locate a usable Python. Prefer the Windows launcher (`py -3`, which selects the
# newest installed 3.x), then `python`, then `python3`. Requires 3.10+.
# Returns an object with the exe + any leading args (e.g. -3) and the version.
# ---------------------------------------------------------------------------
function Resolve-Python {
    $probe = 'import sys; print("%d.%d" % sys.version_info[:2])'
    $candidates = @(
        @{ Exe = 'py';      Pre = @('-3') },
        @{ Exe = 'python';  Pre = @() },
        @{ Exe = 'python3'; Pre = @() }
    )
    foreach ($c in $candidates) {
        if (-not (Get-Command $c.Exe -ErrorAction SilentlyContinue)) { continue }
        $argv = @($c.Pre) + @('-c', $probe)
        $out = $null
        try { $out = (& $c.Exe @argv 2>$null) } catch { continue }
        if ($LASTEXITCODE -ne 0 -or -not $out) { continue }
        $verStr = ("$out").Trim()
        $ver = $null
        if (-not [version]::TryParse($verStr, [ref]$ver)) { continue }
        if ($ver -ge [version]'3.10') {
            return [pscustomobject]@{ Exe = $c.Exe; Pre = @($c.Pre); Version = $ver }
        }
    }
    return $null
}

# ===========================================================================
# BANNER
# ===========================================================================
Write-Host ""
Write-Host "NotebookLM KB System — Windows installer" -ForegroundColor White
Write-Host "----------------------------------------" -ForegroundColor White
Write-Info "KB root : $KbRoot"
Write-Info "Browser : $Browser"
if ($SkipLogin)            { Write-Info "Login   : SKIPPED (-SkipLogin)" }
if ($Recreate)            { Write-Info "Venv    : will be recreated (-Recreate)" }
if ($EnableHeadlessReauth) { Write-Info "Headless: NOTEBOOKLM_HEADLESS_REAUTH will be persisted" }

$venvPath      = Join-Path $KbRoot 'venv'
$venvScripts   = Join-Path $venvPath 'Scripts'
$venvPython    = Join-Path $venvScripts 'python.exe'
$notebooklmExe = Join-Path $venvScripts 'notebooklm.exe'
$playwrightExe = Join-Path $venvScripts 'playwright.exe'

# ===========================================================================
# 1. PYTHON
# ===========================================================================
Write-Step "Checking Python (need 3.10+, 3.11+ recommended)"
$py = Resolve-Python
if (-not $py) {
    Write-Warn2 "No suitable Python found on PATH."
    Write-Info  "Install it, then re-run this script:"
    Write-Info  "    winget install --id Python.Python.3.11 -e --source winget"
    Write-Info  "  or download from https://www.python.org/downloads/windows/"
    Write-Info  "  (tick 'Add python.exe to PATH' in the installer, then open a NEW window)."
    throw "Python 3.10+ is required."
}
Write-Ok ("Found Python {0} via '{1} {2}'" -f $py.Version, $py.Exe, ($py.Pre -join ' ')).Trim()
if ($py.Version -lt [version]'3.11') {
    Write-Warn2 "Python $($py.Version) works, but 3.11+ is recommended."
}

# ===========================================================================
# 2. VIRTUALENV
# ===========================================================================
Write-Step "Creating the virtualenv at $venvPath"
New-Item -ItemType Directory -Force -Path $KbRoot | Out-Null

if ((Test-Path $venvPython) -and -not $Recreate) {
    Write-Ok "venv already exists — reusing it (pass -Recreate to rebuild)."
}
else {
    if ((Test-Path $venvPath) -and $Recreate) {
        Write-Info "Removing existing venv (-Recreate)..."
        Remove-Item -Recurse -Force $venvPath
    }
    $venvArgs = @($py.Pre) + @('-m', 'venv', $venvPath)
    Invoke-Native -Exe $py.Exe -Arguments $venvArgs -What "python -m venv"
    if (-not (Test-Path $venvPython)) {
        throw "venv creation reported success but $venvPython is missing."
    }
    Write-Ok "venv created."
}

# ===========================================================================
# 3. INSTALL THE CLI (with the browser extras)
# ===========================================================================
Write-Step "Installing notebooklm-py[browser,cookies] into the venv"
# Upgrade pip inside the fresh venv first, then install the CLI + its extras
# ([browser] for Playwright-driven login, [cookies] for --browser-cookies).
Invoke-Native -Exe $venvPython -Arguments @('-m', 'pip', 'install', '--upgrade', 'pip') -What "pip upgrade"
Invoke-Native -Exe $venvPython -Arguments @('-m', 'pip', 'install', 'notebooklm-py[browser,cookies]') -What "pip install notebooklm-py[browser,cookies]"

if (-not (Test-Path $notebooklmExe)) {
    throw "Install finished but $notebooklmExe is missing — the CLI did not install correctly."
}
# Confirm the CLI actually runs.
Invoke-Native -Exe $notebooklmExe -Arguments @('--version') -What "notebooklm --version"
Write-Ok "notebooklm CLI installed."

# ===========================================================================
# 4. DETECT THE BROWSER AND CHOOSE THE LOGIN FLAG
# ===========================================================================
Write-Step "Detecting an installed browser"

# Candidate install locations (registry App Paths is checked first inside Find-Browser).
$pf    = $env:ProgramFiles
$pf86  = ${env:ProgramFiles(x86)}
$local = $env:LOCALAPPDATA

$chrome  = Find-Browser -ExeName 'chrome.exe'  -Candidates @(
    (Join-IfBase $pf    'Google\Chrome\Application\chrome.exe'),
    (Join-IfBase $pf86  'Google\Chrome\Application\chrome.exe'),
    (Join-IfBase $local 'Google\Chrome\Application\chrome.exe')
)
$edge    = Find-Browser -ExeName 'msedge.exe'  -Candidates @(
    (Join-IfBase $pf86  'Microsoft\Edge\Application\msedge.exe'),
    (Join-IfBase $pf    'Microsoft\Edge\Application\msedge.exe')
)
$brave   = Find-Browser -ExeName 'brave.exe'   -Candidates @(
    (Join-IfBase $pf    'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (Join-IfBase $pf86  'BraveSoftware\Brave-Browser\Application\brave.exe'),
    (Join-IfBase $local 'BraveSoftware\Brave-Browser\Application\brave.exe')
)
$firefox = Find-Browser -ExeName 'firefox.exe' -Candidates @(
    (Join-IfBase $pf    'Mozilla Firefox\firefox.exe'),
    (Join-IfBase $pf86  'Mozilla Firefox\firefox.exe')
)

# Report what we found.
if ($chrome)  { Write-Info "FOUND  Google Chrome   -> $chrome" }   else { Write-Info "-      Google Chrome   (not found)" }
if ($edge)    { Write-Info "FOUND  Microsoft Edge  -> $edge" }     else { Write-Info "-      Microsoft Edge  (not found)" }
if ($brave)   { Write-Info "FOUND  Brave           -> $brave" }    else { Write-Info "-      Brave           (not found)" }
if ($firefox) { Write-Info "FOUND  Firefox         -> $firefox" }  else { Write-Info "-      Firefox         (not found)" }

# Decide the login arguments and whether the Playwright-managed Chromium is needed.
#   Chromium-family (Chrome/Edge) -> --browser <name>   (launches it for sign-in)
#   Brave/Firefox                 -> --browser-cookies <name>  (reads existing cookies)
#   nothing                       -> playwright install chromium, then --browser chromium
$loginArgs      = $null
$needChromium   = $false
$loginNote      = ''

if ($Browser -ne 'auto') {
    # Explicit override from the caller.
    switch ($Browser) {
        'chrome'   { $loginArgs = @('login', '--browser', 'chrome') }
        'msedge'   { $loginArgs = @('login', '--browser', 'msedge') }
        'chromium' { $loginArgs = @('login', '--browser', 'chromium'); $needChromium = $true }
        'brave'    { $loginArgs = @('login', '--browser-cookies', 'brave');   $loginNote = 'Sign into NotebookLM in Brave first — this reads its cookies.' }
        'firefox'  { $loginArgs = @('login', '--browser-cookies', 'firefox'); $loginNote = 'Sign into NotebookLM in Firefox first — this reads its cookies.' }
    }
    Write-Info "Using forced browser: $Browser"
}
elseif ($chrome) {
    $loginArgs = @('login', '--browser', 'chrome')
    Write-Info "Chosen: Google Chrome (launches for interactive sign-in)."
}
elseif ($edge) {
    $loginArgs = @('login', '--browser', 'msedge')
    Write-Info "Chosen: Microsoft Edge (launches for interactive sign-in)."
}
elseif ($brave) {
    # Brave is Chromium-based, but the CLI's --browser flag only knows chrome/chromium/msedge,
    # so Brave is driven via the cookie-reading path instead.
    $loginArgs = @('login', '--browser-cookies', 'brave')
    $loginNote = 'Sign into NotebookLM in Brave first — this reads its cookies.'
    Write-Info "Chosen: Brave (reads cookies from your signed-in Brave profile)."
}
elseif ($firefox) {
    $loginArgs = @('login', '--browser-cookies', 'firefox')
    $loginNote = 'Sign into NotebookLM in Firefox first — this reads its cookies.'
    Write-Info "Chosen: Firefox (reads cookies from your signed-in Firefox profile)."
}
else {
    # No system browser at all — fall back to a Playwright-managed Chromium.
    $loginArgs = @('login', '--browser', 'chromium')
    $needChromium = $true
    Write-Info "No system browser found — will install a Playwright Chromium to log in with."
}

# ===========================================================================
# 5. INSTALL PLAYWRIGHT CHROMIUM (only when needed)
# ===========================================================================
if ($needChromium) {
    Write-Step "Installing the Playwright-managed Chromium"
    if (-not (Test-Path $playwrightExe)) {
        throw "playwright.exe not found in the venv — the [browser] extra did not install."
    }
    Invoke-Native -Exe $playwrightExe -Arguments @('install', 'chromium') -What "playwright install chromium"
    Write-Ok "Chromium installed."
}

# ===========================================================================
# 6. LOG IN (seeds the reusable session profile)
# ===========================================================================
if ($SkipLogin) {
    Write-Step "Login SKIPPED (-SkipLogin)"
    Write-Info "Log in later with:"
    Write-Info "    & '$notebooklmExe' $($loginArgs -join ' ')"
}
else {
    Write-Step "Logging in to NotebookLM"
    if ($loginNote) { Write-Warn2 $loginNote }
    Write-Info "Running: notebooklm $($loginArgs -join ' ')"
    Write-Info "A browser may open — sign in with your NotebookLM Google account (<YOUR_EMAIL>)."
    try {
        Invoke-Native -Exe $notebooklmExe -Arguments $loginArgs -What "notebooklm login"
        Write-Ok "Login completed — reusable session profile seeded."
    }
    catch {
        # Login is interactive; a closed window / cancelled sign-in returns non-zero.
        # Surface it but don't discard the working install — the user can retry the one command.
        Write-Warn2 "Login did not complete: $($_.Exception.Message)"
        Write-Warn2 "Retry it once with:"
        Write-Warn2 "    & '$notebooklmExe' $($loginArgs -join ' ')"
        $SkipLogin = $true   # skip the verify step below; nothing to verify yet
    }
}

# ===========================================================================
# 7. HEADLESS RE-AUTH (optional persistence)
# ===========================================================================
if ($EnableHeadlessReauth) {
    Write-Step "Persisting NOTEBOOKLM_HEADLESS_REAUTH=1 (user scope)"
    # Set it for this process (so the verify below benefits too) and persist it for
    # future shells, so long/scheduled runs can refresh their own session mid-run.
    $env:NOTEBOOKLM_HEADLESS_REAUTH = '1'
    [Environment]::SetEnvironmentVariable('NOTEBOOKLM_HEADLESS_REAUTH', '1', 'User')
    Write-Ok "Set for this session and persisted for future PowerShell sessions."
}

# ===========================================================================
# 8. VERIFY WITH A REAL OPERATION
# ===========================================================================
if (-not $SkipLogin) {
    Write-Step "Verifying auth (notebooklm list)"
    try {
        Invoke-Native -Exe $notebooklmExe -Arguments @('list') -What "notebooklm list"
        Write-Ok "Auth works — the CLI reached NotebookLM."
    }
    catch {
        Write-Warn2 "Verification failed: $($_.Exception.Message)"
        Write-Warn2 "If this is an auth error, re-run the login command from step 6."
    }
}

# ===========================================================================
# 9. NEXT STEPS
# ===========================================================================
Write-Step "Done. Next steps"
Write-Host @"
    The CLI is installed in a venv at:
        $venvPath

    In every NEW PowerShell window, activate the venv before using the CLI:
        & "$venvScripts\Activate.ps1"
    (If activation is blocked: Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned)

    Create your first notebook and add a source:
        notebooklm create "infra"          # note the <NOTEBOOK_ID> it prints
        New-Item -ItemType Directory -Force -Path "$KbRoot\build" | Out-Null
        Set-Content "$KbRoot\build\infra__architecture.md" "# infra`n`nFirst notes."
        notebooklm source add -n <NOTEBOOK_ID> "$KbRoot\build\infra__architecture.md"
        notebooklm source list -n <NOTEBOOK_ID>         # wait until it shows "ready"

    Record the friendly-key -> id map in $KbRoot\notebooks.json :
        { "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }

    Ask a question (cheap, non-destructive):
        notebooklm ask -n <NOTEBOOK_ID> "<an extensive, context-rich question>"

    Web research: research.sh is a bash script (needs bash + jq), so run it under
    Git Bash or WSL, or call the CLI directly from PowerShell:
        notebooklm source add-research -n <NOTEBOOK_ID> "<topic>" --from web --import-all --mode fast
        `$env:NOTEBOOKLM_HEADLESS_REAUTH = "1"
        notebooklm source add-research -n <NOTEBOOK_ID> "<topic>" --from web --import-all --mode deep

    Full guide: install/windows-powershell.md   Concept + routing: README.md
"@ -ForegroundColor Gray

Write-Host ""
Write-Ok "Installation finished."
