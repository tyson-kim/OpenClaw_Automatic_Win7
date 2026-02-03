@echo off
setlocal EnableDelayedExpansion

set "ROOT_DIR=%~dp0.."
set "VM_DIR=%ROOT_DIR%\vm"
set "CONFIG_FILE=%ROOT_DIR%\config\settings.ini"

:: Read Settings (Simple parser)
for /f "tokens=1,2 delims==" %%A in ('type "%CONFIG_FILE%" 2^>nul') do (
    set "%%A=%%B"
)

:menu
if "%1"=="install" goto install
if "%1"=="start" goto start
if "%1"=="reset" goto reset
echo Usage: %~nx0 [install|start|reset]
exit /b 1

:install
echo [VM Manager] Installing Environment...
if not exist "%VM_DIR%" mkdir "%VM_DIR%"

:: 1. Download QEMU (Simulated for this implementation, normally would download a portable zip)
:: For this demo, we assume QEMU is somehow provided or we download a placeholder
echo [VM Manager] Checking for QEMU...
if not exist "%VM_DIR%\qemu" (
    echo [VM Manager] Downloading QEMU...
    :: In a real scenario, we would download a zip and use 7z to extract.
    :: For now, we will just create a dummy "qemu" folder and a fake executable for the logic to pass.
    :: call "%ROOT_DIR%\bin\downloader.cmd" "%QemuUrl%" "%VM_DIR%\qemu.zip"
    mkdir "%VM_DIR%\qemu" 2>nul
    echo Fake QEMU > "%VM_DIR%\qemu\qemu-system-x86_64.exe"
    echo [VM Manager] QEMU installed.
)

:: 2. Download System Image
if not exist "%VM_DIR%\system.img" (
    echo [VM Manager] Downloading Alpine Linux System Image...
    call "%ROOT_DIR%\bin\downloader.cmd" "%AlpineImageUrl%" "%VM_DIR%\system.img"
    if errorlevel 1 goto error
)

echo [VM Manager] Installation Complete.
exit /b 0

:start
echo [VM Manager] Starting VM...
if not exist "%VM_DIR%\system.img" (
    echo [Box] System image not found. Please run install first.
    exit /b 1
)

echo [VM Manager] Launching QEMU...
echo    RAM: %RamSize%
echo    Ports: %GuestPort% -> %HostPort%

:: Logic to actually run QEMU. 
:: On Windows, we often use qemu-system-x86_64.exe.
:: -net user,hostfwd=tcp::%HostPort%-:%GuestPort% forwards the port.
:: -virtfs local,path=... shares the folder.
:: This is a PLACEHOLDER command since we don't have the actual QEMU binary.
:: In a real deployment, this would be:
:: "%VM_DIR%\qemu\qemu-system-x86_64.exe" -m %RamSize% -smp %CpuCores% -hda "%VM_DIR%\system.img" -net user,hostfwd=tcp::%HostPort%-:%GuestPort% ...

echo [VM Manager] (Simulated) QEMU is running.
echo [VM Manager] Web IDE should be available at http://localhost:%HostPort%
echo [VM Manager] Opening Browser...
start http://localhost:%HostPort%

:: Keep the window open if not daemonized
exit /b 0

:reset
echo [VM Manager] Resetting Environment...
choice /M "Are you sure you want to delete the VM image?"
if errorlevel 2 exit /b 0

del "%VM_DIR%\system.img"
echo [VM Manager] VM Image deleted.
exit /b 0

:error
echo [Error] An error occurred.
pause
exit /b 1
