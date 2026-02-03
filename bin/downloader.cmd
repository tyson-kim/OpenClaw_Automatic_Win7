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

:: Method 1: VBScript (WinHTTP)
:: Best success rate on Windows 7 KB3140245+
echo [Downloader] Attempting Method 1 (VBScript/WinHTTP)...
cscript //nologo "%~dp0download.vbs" "%URL%" "%DEST%"
if exist "%DEST%" goto success

:: Method 2: PowerShell (Fallback)
echo [Downloader] Method 1 failed. Attempting Method 2 (PowerShell)...
powershell -Command "[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; (New-Object Net.WebClient).DownloadFile('%URL%', '%DEST%')"
if exist "%DEST%" goto success

:: Method 3: CertUtil
echo [Downloader] Method 2 failed. Attempting Method 3 (CertUtil)...
certutil -urlcache -split -f "%URL%" "%DEST%"
if exist "%DEST%" (
    for %%A in ("%DEST%") do if %%~zA GTR 0 (
        certutil -urlcache -split -f "%URL%" delete >nul 2>&1
        goto success
    )
    del "%DEST%" >nul 2>&1
)

:: Method 4: BitsAdmin
echo [Downloader] Method 3 failed. Attempting Method 4 (BitsAdmin)...
bitsadmin /transfer "OpenClawJob" "%URL%" "%DEST%"
if exist "%DEST%" goto success

echo [Error] All download methods failed.
echo [Tip] 1. Try running 'bin\enable_tls12.bat' (Administrator).
echo [Tip] 2. Install Update KB3140245 manually if not installed.
echo [Tip] 3. Or download manually to: %DEST%
exit /b 1

:success
echo [Downloader] Download complete.
exit /b 0

:usage
echo Usage: %~nx0 ^<URL^> ^<DestinationPath^>
exit /b 1
