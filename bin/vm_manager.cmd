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

:: QEMU Detection (Hardcoded Check)
call :find_qemu
if "%QEMU_EXE%"=="" (
    echo.
    echo [Error] QEMU not found!
    echo [Info] Searched in:
    echo        - C:\Program Files\qemu\qemu-system-x86_64.exe
    echo        - C:\Program Files (x86)\qemu\qemu-system-x86_64.exe
    echo        - %VM_DIR%\qemu\qemu-system-x86_64.exe
    echo.
    echo [Tip] Please verify QEMU is installed and the file 'qemu-system-x86_64.exe' exists.
    pause
    exit /b 1
)
echo [Check] QEMU detected at: %QEMU_EXE%

:check_iso
if not exist "%VM_DIR%\system.img" (
    echo [Check] Looking for System Image...
    if exist "%VM_DIR%\alpine-virt-3.21.2-x86_64.iso" ren "%VM_DIR%\alpine-virt-3.21.2-x86_64.iso" "system.img" & goto found_img
    if exist "%ROOT_DIR%\system.img" move "%ROOT_DIR%\system.img" "%VM_DIR%\system.img" >nul & goto found_img
    
    echo [VM Manager] Downloading System Image...
    call "%ROOT_DIR%\bin\downloader.cmd" "%AlpineImageUrl%" "%VM_DIR%\system.img"
    if errorlevel 1 goto error
)

:found_img
echo [VM Manager] Installation Complete.
exit /b 0

:start
echo [VM Manager] Starting VM...
call :find_qemu
if "%QEMU_EXE%"=="" (
    echo [Error] QEMU not found. Please install QEMU manually.
    exit /b 1
)
if not exist "%VM_DIR%\system.img" (
    echo [Error] System image not found. Please run Install option.
    exit /b 1
)

echo [VM Manager] Launching QEMU...
echo [Info] Login: root

start "QEMU" "%QEMU_EXE%" ^
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
set /p "delconf=Type 'yes' to delete (VM Image only): "
if /i not "%delconf%"=="yes" exit /b 0
if exist "%VM_DIR%\system.img" del "%VM_DIR%\system.img"
if exist "%VM_DIR%\qemu-setup.exe" del "%VM_DIR%\qemu-setup.exe"
exit /b 0

:find_qemu
set "QEMU_EXE="
:: 1. Check Hardcoded paths (To bypass variable issues)
if exist "C:\Program Files\qemu\qemu-system-x86_64.exe" set "QEMU_EXE=C:\Program Files\qemu\qemu-system-x86_64.exe" & exit /b 0
if exist "C:\Program Files (x86)\qemu\qemu-system-x86_64.exe" set "QEMU_EXE=C:\Program Files (x86)\qemu\qemu-system-x86_64.exe" & exit /b 0

:: 2. Check Local
if exist "%VM_DIR%\qemu\qemu-system-x86_64.exe" set "QEMU_EXE=%VM_DIR%\qemu\qemu-system-x86_64.exe" & exit /b 0

:: 3. Check Env Vars (Legacy)
if exist "%ProgramFiles%\qemu\qemu-system-x86_64.exe" set "QEMU_EXE=%ProgramFiles%\qemu\qemu-system-x86_64.exe" & exit /b 0
if defined ProgramW6432 if exist "%ProgramW6432%\qemu\qemu-system-x86_64.exe" set "QEMU_EXE=%ProgramW6432%\qemu\qemu-system-x86_64.exe" & exit /b 0
exit /b 0

:error
echo [Error] Failed.
pause
exit /b 1
