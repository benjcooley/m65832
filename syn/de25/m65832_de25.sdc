# --------------------------------------------------------------------------
# M65832 DE25-Nano Timing Constraints
#
# Copyright (c) 2026 M65832 Project
# SPDX-License-Identifier: GPL-3.0-or-later
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Clock Definition
# --------------------------------------------------------------------------

# 50 MHz input clock
create_clock -name {CLK_50M} -period 20.000 -waveform {0.000 10.000} [get_ports {CLK_50M}]

# Derive PLL clocks (when PLL is added)
derive_pll_clocks

# --------------------------------------------------------------------------
# Clock Uncertainty
# --------------------------------------------------------------------------

derive_clock_uncertainty

# --------------------------------------------------------------------------
# Input/Output Delays
# --------------------------------------------------------------------------

# UART - relatively relaxed timing (115200 baud is ~8.68us per bit)
set_input_delay -clock CLK_50M -max 5.0 [get_ports {UART_RXD}]
set_input_delay -clock CLK_50M -min 0.0 [get_ports {UART_RXD}]
set_output_delay -clock CLK_50M -max 5.0 [get_ports {UART_TXD}]
set_output_delay -clock CLK_50M -min 0.0 [get_ports {UART_TXD}]

# Reset input
set_input_delay -clock CLK_50M -max 5.0 [get_ports {RST_N}]
set_input_delay -clock CLK_50M -min 0.0 [get_ports {RST_N}]

# LEDs - relaxed timing
set_output_delay -clock CLK_50M -max 5.0 [get_ports {LED[*]}]
set_output_delay -clock CLK_50M -min 0.0 [get_ports {LED[*]}]

# --------------------------------------------------------------------------
# False Paths
# --------------------------------------------------------------------------

# Reset is asynchronous
set_false_path -from [get_ports {RST_N}] -to *

# LEDs are slow output
set_false_path -from * -to [get_ports {LED[*]}]

# --------------------------------------------------------------------------
# SDRAM Timing (directly disabled for initial bring-up)
# --------------------------------------------------------------------------

# SDRAM outputs directly disabled - no timing constraints needed yet
# When SDRAM controller is added, define constraints like:
#   create_generated_clock -name sdram_clk -source [get_pins ...] ...
#   set_output_delay -clock sdram_clk ...
#   set_input_delay -clock sdram_clk ...
