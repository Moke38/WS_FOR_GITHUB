@echo off
rem Start StockMover (browser version). Double-click to run.
cd /d "%~dp0"

where py > nul 2>&1
if %errorlevel%==0 (
    py -3 server.py %*
    goto :end
)
where python > nul 2>&1
if %errorlevel%==0 (
    python server.py %*
    goto :end
)
echo Python was not found. Install it from https://www.python.org/downloads/

:end
pause
