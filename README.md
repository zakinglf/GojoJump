# GojoJump

A vertical platform game written in Verilog for the Basys 3 FPGA. It uses VGA for display and USB-UART for keyboard input.

## Run

1. Open [`GojoJump.xpr`](GojoJump.xpr) in Vivado 2019.1, generate the bitstream, and program the board.
2. Connect a VGA display or capture device.
3. Follow the [keyboard setup guide](host/README.md) to start the Windows keyboard tool. Select the board's USB Serial Port and click Connect.

## Controls

| Key | Action |
| --- | --- |
| A / D or arrow keys | Move left or right |
| K | Jump / double jump |
| Direction + L | Dash |
| J | Attack |
| Hold R | Heal |
| I | Hollow Purple |
| U | Domain Expansion |
| Board center button | Restart |
