@echo off
setlocal
chcp 65001 >nul
set "RESON_POWERSHELL=powershell.exe"
where pwsh.exe >nul 2>nul
if not errorlevel 1 set "RESON_POWERSHELL=pwsh.exe"
"%RESON_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-server\Start-PCServer.ps1" -Lan -Watch %*
set "RESON_EXIT_CODE=%errorlevel%"
echo.
if "%RESON_EXIT_CODE%"=="0" (
  echo Server monitor has closed.
) else (
  echo Failed to start Reson PC server. Check the error above.
)
pause
exit /b %RESON_EXIT_CODE%
