@echo off
cd /d "%~dp0"
"%~dp0runtime\node.exe" "%~dp0runtime\node_modules\wrangler\bin\wrangler.js" login --scopes account:read user:read pages:write workers_kv:write
if errorlevel 1 echo Cloudflare login failed. Check the browser and network, then try again.
echo Return to the app after authorization succeeds.
pause
