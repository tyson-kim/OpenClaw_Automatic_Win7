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
if exist "%DEST%" del "%DEST%"

:: Method 1: PowerShell (Optimized for Win7/Legacy .NET)
:: - Removed 'SecurityProtocol = 3072' which crashes on older .NET (relying on 'enable_tls12.bat' registry fix instead)
:: - Added 'ServerCertificateValidationCallback = {$true}' to bypass expired Root CA errors common on Win7
echo [Downloader] Attempting Method 1 (PowerShell with SSL Bypass)...

powershell -Command "[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; (New-Object Net.WebClient).DownloadFile('%URL%', '%DEST%')"

if exist "%DEST%" goto success

:: Method 2: CertUtil
echo [Downloader] Method 1 failed. Attempting Method 2 (CertUtil)...
certutil -urlcache -split -f "%URL%" "%DEST%"
if exist "%DEST%" (
    for %%A in ("%DEST%") do if %%~zA GTR 0 (
        certutil -urlcache -split -f "%URL%" delete >nul 2>&1
        goto success
    )
    del "%DEST%" >nul 2>&1
)

:: Method 3: BitsAdmin
echo [Downloader] Method 2 failed. Attempting Method 3 (BitsAdmin)...
bitsadmin /transfer "OpenClawJob" "%URL%" "%DEST%"
if exist "%DEST%" goto success

echo [Error] All download methods failed.
echo [Tip] Please manually download the file to: %DEST%
exit /b 1

:success
echo [Downloader] Download complete.
exit /b 0

:usage
echo Usage: %~nx0 ^<URL^> ^<DestinationPath^>
exit /b 1
