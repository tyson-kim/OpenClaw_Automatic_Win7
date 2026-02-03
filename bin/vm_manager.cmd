@echo off
setlocal EnableDelayedExpansion

set "ROOT_DIR=%~dp0.."
set "VM_DIR=%ROOT_DIR%\vm"
set "CONFIG_FILE=%ROOT_DIR%\config\settings.ini"

:: Read Settings
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

:: 1. QEMU Setup
if not exist "%VM_DIR%\qemu\qemu-system-x86_64.exe" (
    :: Check for manual download
    if exist "%VM_DIR%\qemu-setup.exe" (
        echo [VM Manager] Found manual download: qemu-setup.exe. Skipping download.
    ) else (
        echo [VM Manager] Downloading QEMU 7.2.0...
        call "%ROOT_DIR%\bin\downloader.cmd" "%QemuUrl%" "%VM_DIR%\qemu-setup.exe"
        if errorlevel 1 goto error
    )
    
    echo [VM Manager] Installing QEMU silently...
    "%VM_DIR%\qemu-setup.exe" /S /D=%VM_DIR%\qemu
    
    :: Cleanup (Optional: Keep it if user wants to keep the installer)
    :: del "%VM_DIR%\qemu-setup.exe"
    echo [VM Manager] QEMU installed.
)

:: 2. System Image
if not exist "%VM_DIR%\system.img" (
    echo [VM Manager] Downloading System Image...
    call "%ROOT_DIR%\bin\downloader.cmd" "%AlpineImageUrl%" "%VM_DIR%\system.img"
    if errorlevel 1 goto error
)

echo [VM Manager] Installation Complete.
exit /b 0

:start
echo [VM Manager] Starting VM...
if not exist "%VM_DIR%\system.img" (
    echo [Error] System image not found. Please run install first.
    exit /b 1
)
if not exist "%VM_DIR%\qemu\qemu-system-x86_64.exe" (
    echo [Error] QEMU not found. Please run install first.
    exit /b 1
)

echo [VM Manager] Launching QEMU...
echo [Info] Login: root

start "" "%VM_DIR%\qemu\qemu-system-x86_64.exe" ^
    -m %RamSize% ^
    -smp %CpuCores% ^
    -cdrom "%VM_DIR%\system.img" ^
    -net nic,model=e1000 -net user,hostfwd=tcp::%HostPort%-:%GuestPort% ^
    %ImageParams%

echo [VM Manager] VM launched.
echo [VM Manager] Access at: http://localhost:%HostPort%
exit /b 0

:reset
echo [VM Manager] Resetting Environment...
echo WARNING: This will delete the VM image and QEMU.
set /p "delconf=Type 'yes' to confirm: "
if /i not "%delconf%"=="yes" exit /b 0

if exist "%VM_DIR%\system.img" del "%VM_DIR%\system.img"
if exist "%VM_DIR%\qemu" rmdir /s /q "%VM_DIR%\qemu"
if exist "%VM_DIR%\qemu-setup.exe" del "%VM_DIR%\qemu-setup.exe"
echo [VM Manager] Environment reset.
exit /b 0

:error
echo [Error] Installation failed.
echo [Tip] For manual install, download files to '%VM_DIR%' and try again.
pause
exit /b 1
