@echo off
setlocal
set "URL=%~1"
set "DEST=%~2"

if "%URL%"=="" goto usage
if "%DEST%"=="" goto usage

echo [Downloader] Downloading: %URL%
echo [Downloader] To: %DEST%

:: Ensure destination directory exists
for %%I in ("%DEST%") do if not exist "%%~dpI" mkdir "%%~dpI"
:: Remove partial file if exists to ensure clean check
if exist "%DEST%" del "%DEST%"

:: Method 1: PowerShell with TLS 1.2 forced (3072)
echo [Downloader] Attempting Method 1 (PowerShell)...
:: Tried using reflection to bypass Enum check for 3072 on older environments
powershell -Command "[System.Net.ServicePointManager]::SecurityProtocol = 3072; (New-Object System.Net.WebClient).DownloadFile('%URL%', '%DEST%')"
if exist "%DEST%" goto success

:: Method 2: CertUtil
echo [Downloader] Method 1 failed. Attempting Method 2 (CertUtil)...
certutil -urlcache -split -f "%URL%" "%DEST%"
if exist "%DEST%" (
    :: CertUtil sometimes creates empty files on error, check size?
    for %%A in ("%DEST%") do if %%~zA GTR 0 (
        certutil -urlcache -split -f "%URL%" delete >nul 2>&1
        goto success
    )
    :: If zero bytes, delete and continue
    del "%DEST%" >nul 2>&1
)

:: Method 3: BitsAdmin
echo [Downloader] Method 2 failed. Attempting Method 3 (BitsAdmin)...
bitsadmin /transfer "OpenClawJob" "%URL%" "%DEST%"
if exist "%DEST%" goto success

echo [Error] All download methods failed.
echo [Tip] 1. Try running 'bin\enable_tls12.bat' as Administrator.
echo [Tip] 2. Or manually download the file to: %DEST%
exit /b 1

:success
echo [Downloader] Download complete.
exit /b 0

:usage
echo Usage: %~nx0 ^<URL^> ^<DestinationPath^>
exit /b 1
