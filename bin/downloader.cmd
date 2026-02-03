@echo off
setlocal
set "URL=%~1"
set "DEST=%~2"

if "%URL%"=="" goto usage
if "%DEST%"=="" goto usage

echo [Downloader] Downloading: %URL%
echo [Downloader] To: %DEST%

:: Use PowerShell with TLS 1.2 enforced
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('%URL%', '%DEST%')"

if errorlevel 1 (
    echo [Error] Download failed.
    exit /b 1
)

echo [Downloader] Download complete.
exit /b 0

:usage
echo Usage: %~nx0 ^<URL^> ^<DestinationPath^>
exit /b 1
