@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\clean-dsh.ps1" %*
exit /b %errorlevel%
