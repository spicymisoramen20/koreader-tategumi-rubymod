@echo off
REM Double-clickable KOReader launcher for the win32 package.
REM Do not run luajit.exe alone — that opens a blank LuaJIT REPL.
cd /d "%~dp0"
set "PATH=%CD%\libs;%CD%;%PATH%"

set "LJ="
if exist "%CD%\luajit.exe" set "LJ=%CD%\luajit.exe"
if not defined LJ if exist "%CD%\luajit" set "LJ=%CD%\luajit"
if not defined LJ (
  echo ERROR: luajit.exe not found in "%CD%"
  pause
  exit /b 1
)

"%LJ%" reader.lua %*
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo KOReader exited with code %EC%.
  pause
)
exit /b %EC%
