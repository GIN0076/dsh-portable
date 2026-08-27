@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
set "NODE=%ROOT%\runtime\node\node.exe"
set "CLI=%ROOT%\src\apps\cli\lib\bin.js"
set "URL=http://127.0.0.1:3080"

if not exist "%NODE%" (
  echo Built-in Node not found: %NODE%
  exit /b 1
)
if not exist "%CLI%" (
  echo DSH CLI not found: %CLI%
  exit /b 1
)

start "DSH web" /min "%NODE%" "%CLI%" web --host 127.0.0.1 --port 3080
echo Waiting for %URL% ...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='%URL%'; $ok=$false; for($i=0;$i -lt 60;$i++){ try { $r=Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 1; if($r.StatusCode -eq 200){ $ok=$true; break } } catch { Start-Sleep -Milliseconds 500 } }; if(-not $ok){ Write-Host 'DSH web did not start in time.'; exit 1 }"

if errorlevel 1 (
  echo Failed to start DSH web.
  exit /b 1
)

start "" "%URL%"
echo Done. Closing this console window stops the DSH web service.
endlocal
