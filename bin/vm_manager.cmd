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

:: 1. QEMU Setup Checking
if not exist "%VM_DIR%\qemu\qemu-system-x86_64.exe" (
    echo [Check] Looking for QEMU installer...
    
    set "INSTALLER=%VM_DIR%\qemu-setup.exe"
    
    :: Strategy A: Check specific name in VM dir
    if exist "%VM_DIR%\qemu-setup.exe" goto found_qemu
    
    :: Strategy B: Check original filename in VM dir
    if exist "%VM_DIR%\qemu-w64-setup-20221230.exe" (
        set "INSTALLER=%VM_DIR%\qemu-w64-setup-20221230.exe"
        goto found_qemu
    )
    
    :: Strategy C: Check root dir (D:\AgentVM)
    if exist "%ROOT_DIR%\qemu-setup.exe" (
        copy "%ROOT_DIR%\qemu-setup.exe" "%VM_DIR%\qemu-setup.exe" >nul
        goto found_qemu
    )
    if exist "%ROOT_DIR%\qemu-w64-setup-20221230.exe" (
        copy "%ROOT_DIR%\qemu-w64-setup-20221230.exe" "%VM_DIR%\qemu-setup.exe" >nul
        goto found_qemu
    )

    :: Not found, download it
    echo [VM Manager] File not found. Downloading QEMU...
    call "%ROOT_DIR%\bin\downloader.cmd" "%QemuUrl%" "%VM_DIR%\qemu-setup.exe"
    if errorlevel 1 goto error
    goto found_qemu

:found_qemu
    echo [VM Manager] Found installer: !INSTALLER!
    echo [VM Manager] Installing QEMU silently...
    "!INSTALLER!" /S /D=%VM_DIR%\qemu
    echo [VM Manager] QEMU installed.
)

:: 2. System Image Checking
if not exist "%VM_DIR%\system.img" (
    echo [Check] Looking for System Image...
    
    :: Strategy A: Check specific name in VM dir
    if exist "%VM_DIR%\system.img" goto found_img
    
    :: Strategy B: Check original ISO name in VM dir
    if exist "%VM_DIR%\alpine-virt-3.21.2-x86_64.iso" (
        ren "%VM_DIR%\alpine-virt-3.21.2-x86_64.iso" "system.img"
        goto found_img
    )

    :: Strategy C: Check root dir
    if exist "%ROOT_DIR%\system.img" (
        move "%ROOT_DIR%\system.img" "%VM_DIR%\system.img" >nul
        goto found_img
    )
    if exist "%ROOT_DIR%\alpine-virt-3.21.2-x86_64.iso" (
        move "%ROOT_DIR%\alpine-virt-3.21.2-x86_64.iso" "%VM_DIR%\system.img" >nul
        goto found_img
    )

    :: Not found, download it
    echo [VM Manager] Downloading System Image...
    call "%ROOT_DIR%\bin\downloader.cmd" "%AlpineImageUrl%" "%VM_DIR%\system.img"
    if errorlevel 1 goto error
)

:found_img
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
