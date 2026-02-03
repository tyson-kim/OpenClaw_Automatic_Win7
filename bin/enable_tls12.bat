@echo off
echo Enabling TLS 1.2 Support on Windows 7...
echo.

:: 1. Add SchUseStrongCrypto to .NET 4.0/4.5 (64-bit and 32-bit)
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f

:: 2. Add SchUseStrongCrypto to .NET 2.0/3.5 (just in case PowerShell v2 uses it)
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v2.0.50727" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f

:: 3. Set SystemDefaultTlsVersions
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f

echo.
echo Registry keys updated. Please restart the running scripts (and potentially the PC if this doesn't work immediately).
echo.
pause
