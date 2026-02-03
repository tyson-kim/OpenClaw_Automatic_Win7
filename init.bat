@echo off
setlocal
title OpenClaw Dev Environment (Windows 7 Mode)
cls

:: Robust path handling
set "ROOT_DIR=%~dp0"
set "VM_IMG=%ROOT_DIR%vm\system.img"

:main_menu
cls
echo ==================================================
echo       OpenClaw Development Environment
echo                (Windows 7)
echo ==================================================
echo.

:: Use GOTO logic instead of code blocks to safely handle paths with parentheses
if exist "%VM_IMG%" goto menu_installed
goto menu_not_installed

:menu_installed
echo  [Status] Environment Detected via VM.
echo.
echo  1. Start Web IDE - Run VM
echo  2. Reset Environment - Delete VM
echo  3. Exit
echo.
set /p "choice=Select an option: "
if "%choice%"=="1" goto start_ide
if "%choice%"=="2" goto reset_env
if "%choice%"=="3" goto exit_script
goto main_menu

:menu_not_installed
echo  [Status] Environment Not Installed.
echo.
echo  1. Install Environment - Download VM
echo  2. Exit
echo.
set /p "choice=Select an option: "
if "%choice%"=="1" goto install_env
if "%choice%"=="2" goto exit_script
goto main_menu

:install_env
cls
call "%ROOT_DIR%bin\vm_manager.cmd" install
if errorlevel 1 (
    echo Installation failed.
    pause
    goto main_menu
)
echo.
echo Installation complete! You can now start the Web IDE.
:: Force wait to ensure user sees the message
pause
goto main_menu

:start_ide
cls
call "%ROOT_DIR%bin\vm_manager.cmd" start
goto main_menu

:reset_env
cls
call "%ROOT_DIR%bin\vm_manager.cmd" reset
goto main_menu

:exit_script
exit /b 0
