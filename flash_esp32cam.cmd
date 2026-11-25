@echo off
setlocal
echo Smart Room - ESP32-CAM
echo This opens a menu, not an automatic flash.
echo Do not energize the reported COM-L / NO-N wiring.
echo Read docs\hardware.md before using a board or relay.
echo.
if not exist "%~dp0flash_esp32cam.ps1" goto missing
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0flash_esp32cam.ps1" -Interactive
set "helper_exit=%errorlevel%"
echo.
echo Helper finished with exit code %helper_exit%.
echo No automatic retry will be attempted.
pause
exit /b %helper_exit%
:missing
echo The sibling flash_esp32cam.ps1 file is missing. Keep both files in the project.
pause
exit /b 3
