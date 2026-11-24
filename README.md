# GojoJump

GojoJump is an endless vertical platformer built in Verilog for the Basys 3 FPGA. Climb procedurally generated routes, double-jump and dash between platforms, and use Jujutsu Kaisen–inspired abilities against enemies and their projectiles. The FPGA runs the game and renders 640×480 VGA video. A Windows keyboard tool sends input over the board's USB-UART bridge.

## Build and run

**Requirements:** Basys 3 (`xc7a35tcpg236-1`), Vivado 2019.1, a VGA display or compatible capture setup, a USB data cable, and Python 3 with Tkinter on Windows.

1. Open [`GojoJump.xpr`](GojoJump.xpr) in Vivado. The design top is `top`. Keep [the asset directory](assets/) next to the project so Vivado can find the `.mem` files.
2. Generate the bitstream, connect the Basys 3, then use **Hardware Manager → Program Device** to load the generated `top.bit`. Connect the board's VGA output to a display or capture device.
3. From the repository root, open PowerShell and start the keyboard tool:

   ```powershell
   cd host
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r requirements.txt
   .\.venv\Scripts\python.exe keyboard_control.py
   ```

4. In the keyboard tool, select the Basys 3 USB Serial Port and click **Connect** (`连接`). The link uses **115200 baud, 8N1**. Press the board's center button to reset or restart.

See [the keyboard guide](host/README.md) for the byte protocol and serial loopback test.

## Controls

| Key | Action |
| --- | --- |
| **A / D** or **← / →** | Move left or right |
| **K** | Jump. Press again in the air to double-jump |
| **Direction + L** | Dash on the ground or in the air |
| **J** | Melee attack. A successful Black Flash restores cursed energy and refreshes aerial movement |
| **Hold R** | Heal to full when below maximum health, for 1 cursed energy |
| **I** | Fire Hollow Purple for 4 cursed energy |
| **U** | Use Domain Expansion to clear active enemies for 6 cursed energy |
| **Esc** | Toggle keyboard input from the host tool |
| **Board center button** | Reset the game |

Earn points by scrolling upward and defeating enemies. Cursed energy can also absorb a hit. Falling off-screen or running out of health ends the run.

## FPGA design

- **Multi-route generation.** The generator maintains up to three route fronts and recycles off-screen platforms through 44 slots. Candidate spacing is based on player movement, and the generator checks nearby platforms before placing a new one.
- **Frame updates.** The 25 MHz pixel clock drives VGA scanning. At a frame boundary, the game prepares movement, commits positions and scrolling, then evaluates hits on separate clock edges.
- **Video pipeline.** Sprite and scene ROMs feed a layer compositor. Full-screen cutscenes reuse repeated 4×4 tiles to reduce block RAM usage.

| Path | Contents |
| --- | --- |
| [`GojoJump.srcs/sources_1/new/`](GojoJump.srcs/sources_1/new/) | Game logic, collision detection, UART and rendering RTL |
| [`GojoJump.srcs/constrs_1/new/`](GojoJump.srcs/constrs_1/new/) | Basys 3 pin and clock constraints |
| [`GojoJump.srcs/sim_1/new/`](GojoJump.srcs/sim_1/new/) | XSim testbenches, including `tb_uart_rx` and `tb_vga_timing` |
| [`assets/`](assets/) | Sprite and scene data used to initialize ROMs |
| [`host/`](host/) | Windows keyboard-to-UART tool and its dependencies |

## Credits

The project draws on *Doodle Jump* and the [Doodle Jump FPGA reference project](https://github.com/szlee118/Doodle-Jump/tree/8dd4ffbc3fca72059fe51186d7634a2b91bf60da). The characters and abilities are inspired by *Jujutsu Kaisen* by Gege Akutami.
