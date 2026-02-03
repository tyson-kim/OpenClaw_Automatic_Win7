@echo off
setlocal
set "URL=%~1"
set "DEST=%~2"

if "%URL%"=="" goto usage
if "%DEST%"=="" goto usage

echo [Downloader] Downloading: %URL%
echo [Downloader] To: %DEST%

:: Method 1: PowerShell with TLS 1.2 forced (3072)
echo [Downloader] Attempting Method 1 (PowerShell)...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = 3072; (New-Object Net.WebClient).DownloadFile('%URL%', '%DEST%')"
if not errorlevel 1 goto success

:: Method 2: CertUtil (Built-in Windows tool, often works without .NET)
echo [Downloader] Method 1 failed. Attempting Method 2 (CertUtil)...
certutil -urlcache -split -f "%URL%" "%DEST%"
if not errorlevel 1 (
    :: Cleanup CertUtil cache
    certutil -urlcache -split -f "%URL%" delete >nul 2>&1
    goto success
)

:: Method 3: BitsAdmin
echo [Downloader] Method 2 failed. Attempting Method 3 (BitsAdmin)...
bitsadmin /transfer "OpenClawJob" "%URL%" "%DEST%"
if not errorlevel 1 goto success

echo [Error] All download methods failed.
echo [Tip] You may need to download the file manually and place it at: %DEST%
exit /b 1

:success
echo [Downloader] Download complete.
exit /b 0

:usage
echo Usage: %~nx0 ^<URL^> ^<DestinationPath^>
exit /b 1
