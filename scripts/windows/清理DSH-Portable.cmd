@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\clean-dsh.ps1" %*
exit /b %errorlevel%
