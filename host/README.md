# Keyboard controller

The Windows keyboard tool sends input to GojoJump over USB-UART. It requires Python 3 with Tkinter.

## Setup

From the `host` directory, run these commands in PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe keyboard_control.py
```

Select the Basys 3 USB Serial Port and click **Connect** (`连接`). Press **Esc** to toggle keyboard input. If the board keeps moving after an unexpected disconnect, press its center reset button.

## Serial protocol

The controller sends one byte of key state at about 20 ms intervals using 115200 baud, 8N1. Bits 0–7 represent left, right, jump, dash, attack, heal, Domain Expansion, and Hollow Purple. Releasing all keys sends `0x00`.

Use `--list-ports` to list available serial ports, or `--self-test` to run a software loopback test.
