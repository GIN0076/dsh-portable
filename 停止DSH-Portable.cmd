@echo off
setlocal EnableExtensions
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop-dsh.ps1"
exit /b %errorlevel%
