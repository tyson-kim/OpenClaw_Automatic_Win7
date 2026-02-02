<# : batch script
@echo off
setlocal
cd /d "%~dp0"

:: Check for Administrator privileges
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

echo [OpenClaw Installer] Starting setup...
echo.

:: FIX: Windows 7 TLS 1.2 Support for .NET Framework (Required for GitHub Downloads)
echo [Fixing] Enabling TLS 1.2 support...
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v2.0.50727" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>&1

:: Execute this file as a PowerShell script (Compatible with PS v2)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%~f0'))"
:: 에러가 발생해도 계속 진행 (One-Click Strategy)
if %errorlevel% neq 0 (
    echo.
    echo [WARN] Some errors occurred but setup will continue...
)
goto :EOF
#>

# PowerShell Setup Logic Starts Here
# FIX: Use "Continue" instead of "Stop" to prevent early termination on errors
$ErrorActionPreference = "Continue"

# FIX: Force TLS 1.2 using Reflection (Bypasses PS v2 Enum Type Check)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [int]3072
} catch {
    # If direct assignment fails, use Reflection
    try {
        $spm = [System.Net.ServicePointManager]
        $prop = $spm.GetProperty("SecurityProtocol")
        $val = [int]3072
        $prop.SetValue($null, $val, $null)
        Write-Host "TLS 1.2 forced via Reflection." -ForegroundColor Gray
    } catch {
        Write-Host "WARNING: Failed to force TLS 1.2. Info: $_" -ForegroundColor Red
    }
}

# FIX: Use $PWD.Path for reliable path resolution
$ScriptPath = $PWD.Path
$EnvPath = Join-Path $ScriptPath ".env"
$BinPath = Join-Path $EnvPath "bin"
$GitPath = Join-Path $BinPath "git"
$NodePath = Join-Path $BinPath "node"

# --- SMART OS DETECTION ---
Write-Host "Checking Operating System..." -ForegroundColor Gray
$OSVersion = [System.Environment]::OSVersion.Version
$IsWin10OrHigher = $OSVersion.Major -ge 10

if ($IsWin10OrHigher) {
    Write-Host ">> Detected Windows 10/11 (Version $($OSVersion.Major).$($OSVersion.Minor))" -ForegroundColor Cyan
    $NodeVersion = "v20.11.0"
    $InstallDocker = $true
}
else {
    Write-Host ">> Detected Windows 7/Legacy (Version $($OSVersion.Major).$($OSVersion.Minor))" -ForegroundColor Yellow
    $NodeVersion = "v16.20.2"  # Unofficial Backport (Alex313031)
    $InstallDocker = $false
}

# --- Configuration ---
$MinGitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/MinGit-2.43.0-64-bit.zip"
# Detect correct URL based on OS
if ($IsWin10OrHigher) {
    $NodeUrl = "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-win-x64.zip"
} else {
    # Unofficial Backport by Alex313031 for Windows 7 (v16 is most stable for kernel compatibility)
    $NodeUrl = "https://github.com/Alex313031/node16-win7/releases/download/v16.20.2/node-v16.20.2-win-x64.zip"
}
$DockerInstallerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"

# --- Functions ---

function Invoke-DownloadAndExtract {
    param([string]$Url, [string]$DestPath, [string]$Name)
    
    if (Test-Path $DestPath) {
        Write-Host "[$Name] Already installed at $DestPath" -ForegroundColor Green
        return
    }

    $ZipFile = Join-Path $EnvPath "$Name.zip"
    
    Write-Host "[$Name] Downloading..." -ForegroundColor Cyan
    
    # DOWNLOAD: Try multiple methods for Windows 7
    $DownloadSuccess = $false
    
    # Method 1: .NET WebClient (Best for modern OS)
    if (-not $DownloadSuccess) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($Url, $ZipFile)
            $DownloadSuccess = $true
        } catch {
            Write-Host "Warning: Standard download failed. Trying BITS..." -ForegroundColor Gray
        }
    }
    
    # Method 2: BITSAdmin (Windows 7 Native)
    if (-not $DownloadSuccess) {
        # Using Start-Process to handle bitsadmin cleanly
        $BitsCmd = "bitsadmin /transfer OpenClawDL /download /priority FOREGROUND $Url $ZipFile"
        Invoke-Expression $BitsCmd | Out-Null
        if (Test-Path $ZipFile) { $DownloadSuccess = $true }
    }
    
    # Method 3: Manual Fallback (If all else fails)
    if (-not $DownloadSuccess -or (Get-Item $ZipFile).Length -lt 1000) {
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        Write-Host "[ERROR] Automatic Download Failed (Windows 7 Security Issue)" -ForegroundColor Yellow
        Write-Host "Please download the file MANUALLY:" -ForegroundColor White
        Write-Host "URL: $Url" -ForegroundColor Cyan
        Write-Host "SAVE TO: $ZipFile" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------" -ForegroundColor Red
        
        # Open URL in browser for user convenience
        Start-Process $Url
        
        # Smart Detection: Find REAL Downloads folder (Registry Check)
        try {
            # Check 'User Shell Folders' for the known GUID of Downloads
            $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            $DownDir = (Get-ItemProperty $RegPath)."{374DE290-123F-4565-9164-39C4925E467B}"
            if (-not $DownDir) { 
                # Fallback to standard property name if GUID missing
                $DownDir = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders")."{374DE290-123F-4565-9164-39C4925E467B}" 
            }
            if (-not $DownDir) { $DownDir = Join-Path $Home "Downloads" } # Final Fallback
            
            # Expand environment variables if path contains %USERPROFILE%
            $UserDownloads = [System.Environment]::ExpandEnvironmentVariables($DownDir)
        } catch {
            $UserDownloads = Join-Path $Home "Downloads"
        }

        Write-Host "Monitoring Downloads Folder: $UserDownloads" -ForegroundColor Gray
        
        # FIX: PS v2 compatible URL filename extraction (Split-Path fails on URLs)
        $FileName = $Url.Split('/')[-1]
        $DownloadedFile = Join-Path $UserDownloads $FileName
        
        Write-Host "Waiting for: $FileName" -ForegroundColor Gray
        
        $TimeOut = 0
        while (-not (Test-Path $ZipFile)) {
            # Check if file appeared in Downloads folder
            if (Test-Path $DownloadedFile) {
                # Wait for download to finish (check file lock/size stability)
                Start-Sleep -Seconds 2
                try {
                    Move-Item -Path $DownloadedFile -Destination $ZipFile -Force -ErrorAction Stop
                    Write-Host "`nFound file in Downloads! Moving it automatically..." -ForegroundColor Green
                    break
                } catch {
                    # File might be still downloading (locked)
                    Write-Host "." -NoNewline
                }
            }
            
            Start-Sleep -Seconds 1
            $TimeOut++
            
            # If not found after 10 seconds, remind user
            if ($TimeOut -eq 10) {
                Write-Host "`n[Info] Still waiting... If your browser saves to a different folder," -ForegroundColor Yellow
                Write-Host "please manually move '$FileName' to:" -ForegroundColor Yellow
                Write-Host "$ZipFile" -ForegroundColor Cyan
            }
            
            # Optional: Allow user to hit Enter if they saved it directly to target
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Enter') { break }
            }
        }
        Write-Host "`nFile detected! Proceeding..." -ForegroundColor Green
    }

    Write-Host "[$Name] Extracting..." -ForegroundColor Cyan
    
    # EXTRACT: PS v2 Compatible (Shell.Application)
    if (-not (Test-Path $DestPath)) { New-Item -ItemType Directory -Path $DestPath | Out-Null }
    
    $shell = New-Object -ComObject Shell.Application
    $zipFn = $shell.NameSpace($ZipFile)
    $destDir = $shell.NameSpace($DestPath)
    
    # Copy items (Flag 16 = Respond 'Yes' to all)
    $destDir.CopyHere($zipFn.Items(), 16)
    
    # Cleanup Zip
    Remove-Item $ZipFile -Force
    
    # Handle Node.js nested folder structure
    # PS v2 compatible directory listing
    if ($Name -eq "NodeJS") {
        $Nested = Get-ChildItem -Path $DestPath | Where-Object { $_.PSIsContainer -and $_.Name -like "node-v*" } | Select-Object -First 1
        if ($Nested) {
            Move-Item -Path "$($Nested.FullName)\*" -Destination $DestPath -Force
            Remove-Item -Path $Nested.FullName -Force
        }
    }

    Write-Host "[$Name] Installed successfully." -ForegroundColor Green
}

# --- Main Execution ---

Write-Host "=== OpenClaw Environment Setup ===" -ForegroundColor Yellow
Write-Host "Target Node.js Version: $NodeVersion" -ForegroundColor Gray
Write-Host "Docker Installation: $(if($InstallDocker){'Enabled'}else{'Disabled (Win7 Incompatible)'})" -ForegroundColor Gray
Write-Host ""

# 1. Create .env directories
if (-not (Test-Path $EnvPath)) { New-Item -ItemType Directory -Path $EnvPath | Out-Null }
if (-not (Test-Path $BinPath)) { New-Item -ItemType Directory -Path $BinPath | Out-Null }

# 2. Setup Portable Git
Invoke-DownloadAndExtract -Url $MinGitUrl -DestPath $GitPath -Name "Git"
$env:PATH = "$GitPath\cmd;$env:PATH"

# 3. Setup Portable Node.js
# FIX: Force Upgrade from Legacy Node v13 to Unofficial v18
if (Test-Path $NodePath) {
    Try {
        $CurrentNodeVer = & "$NodePath\node.exe" -v
        if ($CurrentNodeVer -like "v13.*") {
            Write-Host "Detected Legacy Node v13. Removing to upgrade to Unofficial v18..." -ForegroundColor Yellow
            Remove-Item -Recurse -Force $NodePath -ErrorAction SilentlyContinue
        }
    } Catch {
        # Ignore errors if node isn't executable or other issues
    }
}

Invoke-DownloadAndExtract -Url $NodeUrl -DestPath $NodePath -Name "NodeJS"
$env:PATH = "$NodePath;$env:PATH"

# Verify Tools
Write-Host "--- Verification ---" -ForegroundColor Gray
git --version
node --version
npm --version

# 4. Check Docker
Write-Host "--- Checking Docker ---" -ForegroundColor Gray

if ($InstallDocker) {
    if (Get-Command "docker" -ErrorAction SilentlyContinue) {
        Write-Host "Docker is already installed." -ForegroundColor Green
    }
    else {
        Write-Host "Docker not found. Downloading Installer..." -ForegroundColor Yellow
        $DockerInstaller = Join-Path $EnvPath "Docker Desktop Installer.exe"
        
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($DockerInstallerUrl, $DockerInstaller)
        
        Write-Host "Installing Docker..." -ForegroundColor Yellow
        Write-Host "IMPORTANT: If the computer restarts, please run 'init.bat' again after reboot." -ForegroundColor Magenta
        
        Start-Process -FilePath $DockerInstaller -ArgumentList "install --quiet" -Wait
        
        Write-Host "Docker installed. Please RESTART if prompted." -ForegroundColor Red
        Write-Host "After restart, run 'init.bat' again."
        Pause
        exit
    }
}
else {
    Write-Host "Skipping Docker install (Windows 7 Mode)." -ForegroundColor Yellow
    Write-Host "Running in Node.js Host Mode." -ForegroundColor Green
    Start-Sleep -Seconds 1
}

# 5. Retrieve OpenClaw Package
# Windows 7 Mode: Extract pre-built openclaw_win7.zip (includes node_modules)
# Windows 10+ Mode: npm tarball or GitHub ZIP
$ProjectDir = Join-Path $ScriptPath "openclaw"

# FIX: Kill stale Node processes to unlock files
Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $ProjectDir)) {
    Write-Host "--- Getting OpenClaw Package ---" -ForegroundColor Cyan
    
    $PackageSuccess = $false
    
    # ========== WINDOWS 7 MODE: Extract openclaw_win7.zip ==========
    $Win7ZipPath = Join-Path $ScriptPath "openclaw_win7.zip"
    
    if ($InstallDocker -eq $false) {
        # Windows 7 detected
        
        # Download from GitHub if not found locally
        if (-not (Test-Path $Win7ZipPath)) {
            Write-Host "Downloading openclaw_win7.zip from GitHub Release..." -ForegroundColor Cyan
            
            $ReleaseUrl = "https://github.com/omtkts/OpenClaw_Automatic_Win7/releases/download/v1.0/openclaw_win7.zip"
            
            try {
                $wc = New-Object System.Net.WebClient
                Write-Host "Download URL: $ReleaseUrl" -ForegroundColor Gray
                Write-Host "This may take a few minutes (1+ GB file)..." -ForegroundColor Yellow
                
                $wc.DownloadFile($ReleaseUrl, $Win7ZipPath)
                
                if ((Test-Path $Win7ZipPath) -and ((Get-Item $Win7ZipPath).Length -gt 100000000)) {
                    Write-Host "Download complete!" -ForegroundColor Green
                } else {
                    Write-Host "[ERROR] Download failed or file corrupted" -ForegroundColor Red
                    Remove-Item $Win7ZipPath -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "" -ForegroundColor Yellow
                Write-Host "Manual download:" -ForegroundColor Yellow
                Write-Host "  $ReleaseUrl" -ForegroundColor White
                Write-Host "" -ForegroundColor Yellow
                Write-Host "Save to:" -ForegroundColor Yellow
                Write-Host "  $Win7ZipPath" -ForegroundColor White
            }
        }
        
        # Extract ZIP
        if (Test-Path $Win7ZipPath) {
            Write-Host "Windows 7 Mode: Extracting openclaw_win7.zip..." -ForegroundColor Cyan
            
            $shell = New-Object -ComObject Shell.Application
            $zipFn = $shell.NameSpace($Win7ZipPath)
            $destDir = $shell.NameSpace($ScriptPath)
            
            try {
                Write-Host "Extracting... (this may take a few minutes)" -ForegroundColor Gray
                $destDir.CopyHere($zipFn.Items(), 16)
                
                $ExtractedDir = Join-Path $ScriptPath "openclaw_win7"
                if (Test-Path $ExtractedDir) {
                    # Remove existing openclaw folder if exists
                    if (Test-Path $ProjectDir) {
                        Write-Host "Removing old openclaw folder..." -ForegroundColor Gray
                        cmd /c "rmdir /s /q `"$ProjectDir`""
                        Start-Sleep -Seconds 2
                    }
                    
                    Rename-Item $ExtractedDir "openclaw"
                    $PackageSuccess = $true
                    Write-Host "openclaw_win7.zip extracted successfully!" -ForegroundColor Green
                    Write-Host "node_modules included (Windows 7 ready)" -ForegroundColor Green
                }
            } catch {
                Write-Host "[WARN] ZIP extraction failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    
    # ========== WINDOWS 10+ MODE: npm tarball ==========
    if (-not $PackageSuccess -and $InstallDocker -ne $false) {
        Write-Host "Windows 10+ Mode: Downloading from npm..." -ForegroundColor Gray
        
        $TarballFile = Join-Path $EnvPath "openclaw.tgz"
        $TempExtractDir = Join-Path $EnvPath "openclaw_temp"
        
        # Step 1: Download tarball
        $TarballDownloaded = $false
        $NpmUrls = @(
            "https://registry.npmmirror.com/openclaw/-/openclaw-2026.2.1.tgz"
        )
        
        foreach ($Url in $NpmUrls) {
            Write-Host "Downloading: $Url" -ForegroundColor Cyan
            try {
                $wc = New-Object System.Net.WebClient
                $wc.DownloadFile($Url, $TarballFile)
                if ((Test-Path $TarballFile) -and ((Get-Item $TarballFile).Length -gt 1000000)) {
                    $TarballDownloaded = $true
                    Write-Host "Download successful!" -ForegroundColor Green
                    break
                }
            } catch {
                Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        
        # Step 2: Extract tarball
        if ($TarballDownloaded) {
            Write-Host "Extracting tarball..." -ForegroundColor Cyan
            
            if (Test-Path $TempExtractDir) { cmd /c "rmdir /s /q `"$TempExtractDir`"" }
            New-Item -ItemType Directory -Path $TempExtractDir -Force | Out-Null
            
            $TarSuccess = $false
            
            # Try 7-Zip if installed
            $SevenZipPaths = @("C:\Program Files\7-Zip\7z.exe", "C:\Program Files (x86)\7-Zip\7z.exe")
            foreach ($SevenZip in $SevenZipPaths) {
                if (Test-Path $SevenZip) {
                    Write-Host "Using 7-Zip..." -ForegroundColor Gray
                    cmd /c "`"$SevenZip`" x `"$TarballFile`" -o`"$TempExtractDir`" -y" | Out-Null
                    $InnerTar = Get-ChildItem $TempExtractDir -Filter "*.tar" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($InnerTar) {
                        cmd /c "`"$SevenZip`" x `"$($InnerTar.FullName)`" -o`"$TempExtractDir`" -y" | Out-Null
                    }
                    $TarSuccess = $true
                    break
                }
            }
            
            # Try Git tar
            if (-not $TarSuccess) {
                $GitBinPath = Join-Path $EnvPath "bin\git"
                $TarPaths = @(
                    (Join-Path $GitBinPath "usr\bin\tar.exe"),
                    (Join-Path $GitBinPath "mingw64\bin\tar.exe")
                )
                foreach ($TarPath in $TarPaths) {
                    if (Test-Path $TarPath) {
                        Write-Host "Using Git tar..." -ForegroundColor Gray
                        cmd /c "`"$TarPath`" -xzf `"$TarballFile`" -C `"$TempExtractDir`""
                        if ($LASTEXITCODE -eq 0) { $TarSuccess = $true; break }
                    }
                }
            }
            
            # Move extracted package to ProjectDir
            if ($TarSuccess) {
                $ExtractedPackage = Join-Path $TempExtractDir "package"
                if (Test-Path $ExtractedPackage) {
                    Move-Item $ExtractedPackage $ProjectDir -Force
                    $PackageSuccess = $true
                    Write-Host "npm package installed!" -ForegroundColor Green
                }
            }
            
            # Cleanup
            Remove-Item $TarballFile -Force -ErrorAction SilentlyContinue
            if (Test-Path $TempExtractDir) { cmd /c "rmdir /s /q `"$TempExtractDir`"" }
        }
    }
    
    # ========== FALLBACK: GitHub ZIP (both modes) ==========
    if (-not $PackageSuccess) {
        Write-Host "--------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "Fallback: GitHub ZIP download (browser method)..." -ForegroundColor Yellow
        Write-Host "--------------------------------------------------------" -ForegroundColor Yellow
        
        $SourceZipUrl = "https://github.com/openclaw/openclaw/archive/refs/heads/main.zip"
        Start-Process $SourceZipUrl
        
        # Find Downloads folder
        try {
            $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            $DownDir = (Get-ItemProperty $RegPath)."{374DE290-123F-4565-9164-39C4925E467B}"
            $UserDownloads = [System.Environment]::ExpandEnvironmentVariables($DownDir)
        } catch {
            $UserDownloads = Join-Path $Home "Downloads"
        }
        $DownloadedSource = Join-Path $UserDownloads "openclaw-main.zip"
        $SourceZipFile = Join-Path $EnvPath "source.zip"
        
        Write-Host "Waiting for 'openclaw-main.zip' in Downloads..." -ForegroundColor Gray
        $Timeout = 0
        while ((-not (Test-Path $SourceZipFile)) -and ($Timeout -lt 300)) {
            if (Test-Path $DownloadedSource) {
                Start-Sleep -Seconds 2
                try { Move-Item $DownloadedSource $SourceZipFile -Force -ErrorAction Stop; break } catch {}
            }
            Start-Sleep -Seconds 1
            $Timeout++
        }
        
        if (Test-Path $SourceZipFile) {
            Write-Host "Extracting GitHub ZIP..." -ForegroundColor Cyan
            $shell = New-Object -ComObject Shell.Application
            $zipFn = $shell.NameSpace($SourceZipFile)
            $destDir = $shell.NameSpace($ScriptPath)
            $destDir.CopyHere($zipFn.Items(), 16)
            
            $ExtractedDir = Join-Path $ScriptPath "openclaw-main"
            if (Test-Path $ExtractedDir) {
                # Remove existing openclaw if exists
                if (Test-Path $ProjectDir) { cmd /c "rmdir /s /q `"$ProjectDir`"" }
                Rename-Item $ExtractedDir "openclaw"
                $PackageSuccess = $true
                Write-Host "GitHub source installed!" -ForegroundColor Green
            }
            Remove-Item $SourceZipFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    if (-not $PackageSuccess) {
        Write-Host "[WARN] Failed to get OpenClaw package. Will retry on next run." -ForegroundColor Yellow
        # 에러여도 계속 진행 - 나중에 다시 시도할 수 있음
    }
}
else {
    Write-Host "OpenClaw already exists. Skipping download." -ForegroundColor Green
}

# =============================================================================
# DEPENDENCY INSTALLATION - Multi-Fallback Strategy (Never Exit)
# =============================================================================

# GUARD: Skip if ProjectDir doesn't exist
if (-not (Test-Path $ProjectDir)) {
    Write-Host "[WARN] OpenClaw folder not found. Skipping dependency installation." -ForegroundColor Yellow
    Write-Host "Server will likely fail - please run init.bat again." -ForegroundColor Yellow
} else {
    # Change to project directory for npm install
    Set-Location $ProjectDir

# Check if we actually need ts-node
$DistPath = Join-Path $ProjectDir "dist\index.js"
$NeedsTsNode = -not (Test-Path $DistPath)

if ($NeedsTsNode) {
    Write-Host "Source code detected (no dist/). ts-node required." -ForegroundColor Gray
} else {
    Write-Host "Pre-compiled dist/ found. ts-node NOT required." -ForegroundColor Green
}

# FIX: Windows 7 SSL 설정
cmd /c "git config --global http.sslVerify false" 2>$null
cmd /c "npm config set strict-ssl false" 2>$null
cmd /c "npm config set engine-strict false" 2>$null
cmd /c "npm config set registry https://registry.npmmirror.com/" 2>$null

$TsNodePath = Join-Path $ProjectDir "node_modules\.bin\ts-node.cmd"
$NodeModulesPath = Join-Path $ProjectDir "node_modules"
$NpmRegistry = "https://registry.npmmirror.com/"
$NpmArgs = "--registry $NpmRegistry --ignore-scripts --no-audit --legacy-peer-deps --no-engine-strict --prefer-offline"

# Clean incomplete installations
if ((Test-Path $NodeModulesPath) -and $NeedsTsNode -and (-not (Test-Path $TsNodePath))) {
    Write-Host "Cleaning incomplete installation..." -ForegroundColor Yellow
    cmd /c "rmdir /s /q `"$NodeModulesPath`"" 2>$null
    Start-Sleep -Seconds 1
}

# Create node_modules if not exists
if (-not (Test-Path $NodeModulesPath)) {
    New-Item -ItemType Directory -Path $NodeModulesPath -Force | Out-Null
}

# =============================================================================
# STRATEGY: Direct Tarball Download (bypasses npm network issues)
# =============================================================================

if ($NeedsTsNode -and (-not (Test-Path $TsNodePath))) {
    Write-Host "=== Installing ts-node via Direct Tarball Download ===" -ForegroundColor Cyan
    
    $TarballDir = Join-Path $EnvPath "tarballs"
    if (-not (Test-Path $TarballDir)) { New-Item -ItemType Directory -Path $TarballDir -Force | Out-Null }
    
    # Packages to download directly
    $Packages = @(
        @{Name="ts-node"; Version="10.9.2"; Url="https://registry.npmmirror.com/ts-node/-/ts-node-10.9.2.tgz"},
        @{Name="typescript"; Version="4.9.5"; Url="https://registry.npmmirror.com/typescript/-/typescript-4.9.5.tgz"},
        @{Name="@types/node"; Version="18.19.0"; Url="https://registry.npmmirror.com/@types/node/-/node-18.19.0.tgz"}
    )
    
    foreach ($Pkg in $Packages) {
        $TgzFile = Join-Path $TarballDir "$($Pkg.Name -replace '/', '_').tgz"
        $PkgDir = Join-Path $NodeModulesPath $Pkg.Name
        
        # Skip if already installed
        if (Test-Path $PkgDir) {
            Write-Host "$($Pkg.Name) already exists" -ForegroundColor Gray
            continue
        }
        
        Write-Host "Downloading $($Pkg.Name)@$($Pkg.Version)..." -ForegroundColor Cyan
        
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($Pkg.Url, $TgzFile)
            
            if ((Test-Path $TgzFile) -and ((Get-Item $TgzFile).Length -gt 10000)) {
                Write-Host "  Downloaded! Extracting..." -ForegroundColor Green
                
                # Find or download 7-Zip
                $SevenZip = $null
                $SevenZipPaths = @(
                    "C:\Program Files\7-Zip\7z.exe",
                    "C:\Program Files (x86)\7-Zip\7z.exe",
                    (Join-Path $EnvPath "7zr.exe")
                )
                
                foreach ($Path in $SevenZipPaths) {
                    if (Test-Path $Path) { $SevenZip = $Path; break }
                }
                
                # Auto-download portable 7zr.exe if not found
                if (-not $SevenZip) {
                    Write-Host "  Downloading portable 7-Zip..." -ForegroundColor Yellow
                    $SevenZrPath = Join-Path $EnvPath "7zr.exe"
                    $SevenZrUrls = @(
                        "https://registry.npmmirror.com/-/binary/7-zip/23.01/7zr.exe",
                        "https://www.7-zip.org/a/7zr.exe"
                    )
                    foreach ($Url in $SevenZrUrls) {
                        try {
                            $wc2 = New-Object System.Net.WebClient
                            $wc2.DownloadFile($Url, $SevenZrPath)
                            if ((Test-Path $SevenZrPath) -and ((Get-Item $SevenZrPath).Length -gt 100000)) {
                                $SevenZip = $SevenZrPath
                                Write-Host "  7zr.exe downloaded!" -ForegroundColor Green
                                break
                            }
                        } catch {}
                    }
                }
                
                $ExtractSuccess = $false
                
                # Extract if we have 7-Zip
                if ($SevenZip -and (Test-Path $SevenZip)) {
                    $TempDir = Join-Path $TarballDir "temp_$($Pkg.Name -replace '/', '_')"
                    if (Test-Path $TempDir) { cmd /c "rmdir /s /q `"$TempDir`"" }
                    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
                    
                    cmd /c "`"$SevenZip`" x `"$TgzFile`" -o`"$TempDir`" -y" 2>$null | Out-Null
                    $InnerTar = Get-ChildItem $TempDir -Filter "*.tar" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($InnerTar) {
                        cmd /c "`"$SevenZip`" x `"$($InnerTar.FullName)`" -o`"$TempDir`" -y" 2>$null | Out-Null
                    }
                    
                    # Move package folder to node_modules
                    $ExtractedPkg = Join-Path $TempDir "package"
                    if (Test-Path $ExtractedPkg) {
                        # Handle scoped packages (@types/node)
                        if ($Pkg.Name -like "@*/*") {
                            $ScopeDir = Join-Path $NodeModulesPath ($Pkg.Name -split '/')[0]
                            if (-not (Test-Path $ScopeDir)) { New-Item -ItemType Directory -Path $ScopeDir -Force | Out-Null }
                        }
                        Move-Item $ExtractedPkg $PkgDir -Force
                        $ExtractSuccess = $true
                        Write-Host "  Installed: $($Pkg.Name)" -ForegroundColor Green
                    }
                    
                    cmd /c "rmdir /s /q `"$TempDir`"" 2>$null
                }
                
                if (-not $ExtractSuccess) {
                    Write-Host "  [WARN] Extraction failed." -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
        Remove-Item $TgzFile -Force -ErrorAction SilentlyContinue
    }
    
    # Create bin stubs for ts-node
    $BinDir = Join-Path $NodeModulesPath ".bin"
    if (-not (Test-Path $BinDir)) { New-Item -ItemType Directory -Path $BinDir -Force | Out-Null }
    
    $TsNodeEntry = Join-Path $NodeModulesPath "ts-node\dist\bin.js"
    if (Test-Path $TsNodeEntry) {
        $TsNodeCmd = Join-Path $BinDir "ts-node.cmd"
        $CmdContent = "@echo off`r`nnode `"%~dp0\..\ts-node\dist\bin.js`" %*"
        Set-Content -Path $TsNodeCmd -Value $CmdContent -Encoding ASCII
        Write-Host "Created ts-node.cmd stub" -ForegroundColor Green
    }
}

# Fallback: Try npm install if tarball method didn't work
if ($NeedsTsNode -and (-not (Test-Path $TsNodePath))) {
    Write-Host "Tarball method failed. Trying npm install..." -ForegroundColor Yellow
    cmd /c "npm install ts-node@10 typescript@4.9 --save-dev $NpmArgs --force" 2>$null
}

# === FINAL STATUS ===
if ($NeedsTsNode) {
    if (Test-Path $TsNodePath) {
        Write-Host "ts-node ready!" -ForegroundColor Green
    } else {
        Write-Host "========================================================" -ForegroundColor Red
        Write-Host "[ERROR] ts-node installation failed." -ForegroundColor Red
        Write-Host "" -ForegroundColor Red
        Write-Host "To fix this:" -ForegroundColor Yellow
        Write-Host "1. Install 7-Zip from https://7-zip.org" -ForegroundColor White
        Write-Host "2. Run init.bat again" -ForegroundColor White
        Write-Host "========================================================" -ForegroundColor Red
    }
} else {
    Write-Host "Dependencies ready! (Using pre-compiled dist/)" -ForegroundColor Green
}

} # End of dependency installation guard (if ProjectDir exists)

# 6. Generate IDE Wrapper
$WrapperPath = Join-Path $ScriptPath "ide-wrapper.html"
$WrapperContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenClaw AI Studio</title>
    <style>
        body, html { margin: 0; padding: 0; height: 100%; overflow: hidden; background: #1e1e1e; font-family: 'Segoe UI', sans-serif; }
        .container { display: flex; height: 100vh; }
        .pane { height: 100%; display: flex; flex-direction: column; }
        .left { width: 60%; border-right: 2px solid #333; }
        .right { width: 40%; background: #252526; }
        iframe { flex: 1; border: none; width: 100%; height: 100%; }
        .header { background: #333; color: #ccc; padding: 5px 15px; font-size: 0.9rem; display: flex; align-items: center; justify-content: space-between; height: 30px; }
        .header span { font-weight: 600; }
        .header button { background: #0e639c; color: white; border: none; padding: 4px 10px; cursor: pointer; border-radius: 2px; }
        .header button:hover { background: #1177bb; }
        .drop-zone { position: absolute; top:0; left:0; right:0; bottom:0; background: rgba(0,0,0,0.8); color: white; display: none; justify-content: center; align-items: center; font-size: 2rem; z-index: 1000; pointer-events: none; }
    </style>
</head>
<body>
    <div class="container">
        <!-- Left Pane: Preview / Workspace -->
        <div class="pane left">
            <div class="header">
                <span>PREVIEW / WORKSPACE</span>
                <button onclick="document.getElementById('preview-frame').src = document.getElementById('preview-frame').src">Refresh</button>
            </div>
            <iframe id="preview-frame" src="about:blank"></iframe>
        </div>
        
        <!-- Right Pane: OpenClaw Chat -->
        <div class="pane right">
            <div class="header">
                <span>OPENCLAW CHAT</span>
                <button onclick="document.getElementById('chat-frame').src = 'http://localhost:3000'">Reload Chat</button>
            </div>
            <iframe id="chat-frame" src="http://localhost:3000"></iframe>
        </div>
    </div>
    <script>
        const preview = document.getElementById('preview-frame');
        preview.contentDocument.write('<body style="background:#1e1e1e;color:#888;display:flex;flex-direction:column;justify-content:center;align-items:center;height:100vh;margin:0;font-family:sans-serif;"><h2>Workspace Ready</h2><p>Ask OpenClaw to create something.</p></body>');
    </script>
</body>
</html>
"@

Set-Content -Path $WrapperPath -Value $WrapperContent -Encoding UTF8
Write-Host "Generated IDE Wrapper at $WrapperPath" -ForegroundColor Green

# 6.5 Generate Windows 7 Compatible TSConfig
# FIX: In-Memory Transpilation Strategy (Run Modern TS on Node 16)
$TsConfigPath = Join-Path $ScriptPath "tsconfig.win7.json"
$TsConfigContent = @"
{
  "compilerOptions": {
    "target": "ES2019",
    "module": "CommonJS",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "strict": false
  },
  "ts-node": {
    "transpileOnly": true,
    "compilerOptions": {
      "module": "CommonJS"
    }
  }
}
"@
Set-Content -Path $TsConfigPath -Value $TsConfigContent -Encoding UTF8
Write-Host "Generated Compatibility Config: $TsConfigPath" -ForegroundColor Green

# 6.55 Generate Runtime Compatibility Shim (Polyfills for Node 16)
$ShimPath = Join-Path $ScriptPath "runtime-compat.js"
$ShimContent = @"
// [Runtime Compatibility Shim for Windows 7 / Node 16]
// Adds missing features from Node 18/20/22 to the Node 16 environment.

const crypto = require('crypto');

// 1. Polyfill crypto.randomUUID (Added in Node 15.6, but ensuring availability)
if (!crypto.randomUUID) {
    crypto.randomUUID = function() {
        return ([1e7]+-1e3+-4e3+-8e3+-1e11).replace(/[018]/g, c =>
            (c ^ crypto.randomBytes(1)[0] & 15 >> c / 4).toString(16)
        );
    };
}

// 2. Polyfill globalThis (Standard in Node 12+, but safely ensuring)
if (typeof globalThis === 'undefined') {
    global.globalThis = global;
}

// 3. Polyfill Array.prototype.at (Added in Node 16.6)
if (!Array.prototype.at) {
    Array.prototype.at = function(n) {
        n = Math.trunc(n) || 0;
        if (n < 0) n += this.length;
        if (n < 0 || n >= this.length) return undefined;
        return this[n];
    };
}

// 4. Polyfill String.prototype.at
if (!String.prototype.at) {
    String.prototype.at = function(n) {
        n = Math.trunc(n) || 0;
        if (n < 0) n += this.length;
        if (n < 0 || n >= this.length) return undefined;
        return this.charAt(n);
    };
}

// 5. Polyfill Promise.withResolvers (Node 22 feature)
if (!Promise.withResolvers) {
    Promise.withResolvers = function() {
        let resolve, reject;
        const promise = new Promise((res, rej) => {
            resolve = res;
            reject = rej;
        });
        return { promise, resolve, reject };
    };
}

// 6. Polyfill Object.groupBy (Node 21 feature)
if (!Object.groupBy) {
    Object.groupBy = function(items, callback) {
        return items.reduce((acc, item) => {
            const key = callback(item);
            if (!acc[key]) acc[key] = [];
            acc[key].push(item);
            return acc;
        }, {});
    };
}

// 7. Polyfill Map.groupBy (Node 21 feature)
if (!Map.groupBy) {
    Map.groupBy = function(items, callback) {
        const map = new Map();
        for (const item of items) {
            const key = callback(item);
            if (!map.has(key)) map.set(key, []);
            map.get(key).push(item);
        }
        return map;
    };
}

console.log('[System] Runtime Compatibility Shim Loaded: Node 16 patched to mimic Node 22+');
"@
Set-Content -Path $ShimPath -Value $ShimContent -Encoding UTF8
Write-Host "Generated Runtime Shim: $ShimPath" -ForegroundColor Green

# 6.6 Generate Native Module Stubs (for Windows 7 compatibility)
# These stub out native modules that require Node 22+ binaries
$NativeStubsPath = Join-Path $ScriptPath "native-stubs.js"
$NativeStubsContent = @"
// [Native Module Stubs for Windows 7 / Node 16]
// Provides fallback implementations for modules requiring native binaries

const Module = require('module');
const originalRequire = Module.prototype.require;

const STUBBED_MODULES = {
    'sharp': {
        // Stub image processing - return no-op functions
        default: () => ({
            resize: () => ({ toBuffer: async () => Buffer.from([]) }),
            toBuffer: async () => Buffer.from([]),
            metadata: async () => ({ width: 0, height: 0 }),
            png: function() { return this; },
            jpeg: function() { return this; },
            webp: function() { return this; }
        })
    },
    'sqlite-vec': {
        // Stub vector database - disabled on Win7
        load: () => console.warn('[STUB] sqlite-vec disabled on Windows 7'),
        getLoadablePath: () => null
    },
    '@lydell/node-pty': {
        // Stub terminal - disabled on Win7
        spawn: () => {
            console.warn('[STUB] node-pty disabled on Windows 7');
            return {
                onData: () => {},
                onExit: () => {},
                write: () => {},
                kill: () => {},
                resize: () => {}
            };
        }
    }
};

Module.prototype.require = function(id) {
    if (STUBBED_MODULES[id]) {
        console.warn('[COMPAT] Using stub for: ' + id);
        return STUBBED_MODULES[id];
    }
    return originalRequire.apply(this, arguments);
};

console.log('[System] Native Module Stubs Loaded: sharp, sqlite-vec, node-pty stubbed');
"@
Set-Content -Path $NativeStubsPath -Value $NativeStubsContent -Encoding UTF8
Write-Host "Generated Native Stubs: $NativeStubsPath" -ForegroundColor Green

# 7. Generate 'start.bat' (Daily Launcher)
$StartScriptPath = Join-Path $ScriptPath "start.bat"
$StartScriptContent = @"
@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

:: [OpenClaw Launcher - Windows 7 One-Click]
:: Runs pre-compiled JavaScript from dist/ folder

set "SCRIPT_DIR=%~dp0"
set "ENV_PATH=%SCRIPT_DIR%.env"
set "NODE_EXE=%ENV_PATH%\bin\node\node.exe"
set "GIT_PATH=%ENV_PATH%\bin\git\cmd"
set "PROJECT_DIR=%SCRIPT_DIR%openclaw"

:: Check node.exe exists
if not exist "%NODE_EXE%" (
    echo [ERROR] Node.js not found at: %NODE_EXE%
    echo Please run 'init.bat' first.
    timeout /t 5
    exit /b
)

:: Add Portable Tools to PATH temporarily
set "PATH=%ENV_PATH%\bin\node;%GIT_PATH%;%PATH%"

:: Launch Browser Wrapper (silent)
if exist "%SCRIPT_DIR%ide-wrapper.html" (
    start "" "%SCRIPT_DIR%ide-wrapper.html"
)

:: [Cleanup] Kill existing Node process to free up Port 3000
taskkill /IM node.exe /F 2>nul

:: Check project directory
if not exist "%PROJECT_DIR%" (
    echo [ERROR] 'openclaw' directory not found!
    echo Please run 'init.bat' first.
    timeout /t 5
    exit /b
)

cd /d "%PROJECT_DIR%"
echo.
echo ========================================================
echo [OpenClaw AI Server - Windows 7 Compatibility Mode]
echo Do NOT close this window while using the AI.
echo ========================================================
echo.

:: AUTO-DETECT: npm package (dist/) or source code (src/)
if exist "dist\index.js" goto :RUN_DIST
if exist "src\index.ts" goto :RUN_SRC
goto :NO_ENTRY

:RUN_DIST
echo [Mode] Running pre-compiled JavaScript from dist/
"%NODE_EXE%" -r "%SCRIPT_DIR%runtime-compat.js" -r "%SCRIPT_DIR%native-stubs.js" dist/index.js
goto :SERVER_END

:RUN_SRC
echo [Mode] Running TypeScript source with ts-node
set "TS_NODE_PROJECT=%SCRIPT_DIR%tsconfig.win7.json"
if exist "node_modules\.bin\ts-node.cmd" (
    call node_modules\.bin\ts-node.cmd -r "%SCRIPT_DIR%runtime-compat.js" -r "%SCRIPT_DIR%native-stubs.js" src/index.ts
) else (
    echo [ERROR] ts-node not found! Run init.bat again.
)
goto :SERVER_END

:NO_ENTRY
echo [ERROR] Neither dist/index.js nor src/index.ts found!

:SERVER_END
echo.
echo [Server Stopped]
echo.
echo Press any key to close this window...
pause >nul
"@

Set-Content -Path $StartScriptPath -Value $StartScriptContent -Encoding UTF8
Write-Host "Generated Launcher: $StartScriptPath" -ForegroundColor Green

# 8. Launch
Write-Host "--- Starting OpenClaw ---" -ForegroundColor Green
Write-Host "Launching start.bat..."

# Run the new launcher only (it will open the browser)
Start-Process $StartScriptPath

Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Complete! Server starting..." -ForegroundColor Green
Write-Host "Browser should open automatically." -ForegroundColor Green
Write-Host "This window will close in 3 seconds..." -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Green
Start-Sleep -Seconds 3
# NO Read-Host - Fully automatic one-click setup!
