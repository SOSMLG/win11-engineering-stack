@echo off
rem one click: elevates, runs the IoT post-install profile, exits clean on success.
rem extra flags pass straight through: Setup.cmd -SkipApps / -ConfigsOnly / -Minimal / -NoDebloat ...
cd /d "%~dp0"
fltmc >nul 2>&1
if "%errorlevel%"=="0" goto run
rem probe failed: if we already bounced through uac, the probe is the broken part. run.
if defined WI_ELEVATED goto run
set "WI_ELEVATED=1"
echo need admin, asking...
set "WI_SELF=%~f0"
if "%~1"=="" (
  powershell -NoProfile -Command "Start-Process -FilePath $env:WI_SELF -Verb RunAs"
) else (
  set "WI_ARGS=%*"
  powershell -NoProfile -Command "Start-Process -FilePath $env:WI_SELF -ArgumentList $env:WI_ARGS -Verb RunAs"
)
exit /b
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" -Profile iot -Unattended %*
if errorlevel 1 (
  echo.
  echo setup failed. log + report live in C:\Windows\Logs\Win-Iot-Setup
  echo fix the error above, then re-run.
  pause
  exit /b 1
)
echo.
echo all done. log + report live in C:\Windows\Logs\Win-Iot-Setup
exit /b 0
