# Use 3.3 V logic for all top-level ports.
set_property IOSTANDARD LVCMOS33 [get_ports *]

# 100 MHz board clock.
set_property PACKAGE_PIN W5 [get_ports clk]
create_clock -name sys_clk -period 10.000 [get_ports clk]

# Center pushbutton: active-high reset.
set_property PACKAGE_PIN U18 [get_ports rst]

# VGA red channel.
set_property PACKAGE_PIN G19 [get_ports {vga_red[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_red[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_red[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_red[3]}]

# VGA green channel.
set_property PACKAGE_PIN J17 [get_ports {vga_green[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_green[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_green[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_green[3]}]

# VGA blue channel.
set_property PACKAGE_PIN N18 [get_ports {vga_blue[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_blue[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_blue[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_blue[3]}]

# VGA synchronization signals.
set_property PACKAGE_PIN P19 [get_ports vga_hsync]
set_property PACKAGE_PIN R19 [get_ports vga_vsync]

# Define the divide-by-four pixel clock.
create_generated_clock -name pixel_clk \
    -source [get_ports clk] \
    -divide_by 4 \
    [get_pins {clk_div_reg[1]/Q}]

# Specify the board configuration voltage.
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# UART input from the onboard USB-UART bridge.
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports rx]