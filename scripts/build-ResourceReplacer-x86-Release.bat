@echo off
setlocal
set "Configuration=Release"
call "%~dp0build-ResourceReplacer-x86.bat" %*
exit /b %errorlevel%
