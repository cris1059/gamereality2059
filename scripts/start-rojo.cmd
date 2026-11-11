@echo off
set "ROJO_EXE=tools\rojo\rojo.exe"
if exist "%ROJO_EXE%" goto serve
where rojo >nul 2>nul
if errorlevel 1 (
  echo Rojo is not installed locally or on PATH. Follow README.md first.
  exit /b 1
)
set "ROJO_EXE=rojo"
:serve
"%ROJO_EXE%" serve default.project.json --port 34872
