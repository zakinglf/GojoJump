@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Python environment missing. See README.md.
    pause
    exit /b 1
)
rem Use the Tcl/Tk libraries bundled with the virtual environment's Python.
set "TCL_LIBRARY="
set "TK_LIBRARY="
rem Ignore Python environment variables inherited from Vivado.
".venv\Scripts\python.exe" -E "keyboard_control.py" %*
if errorlevel 1 pause
