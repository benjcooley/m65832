#!/bin/sh
set -e

ghdl -a --std=08 \
  rtl/m65832_pkg.vhd \
  rtl/m65832_alu.vhd \
  rtl/m65832_regfile.vhd \
  rtl/m65832_addrgen.vhd \
  rtl/m65832_decoder.vhd \
  rtl/m65832_mmu.vhd \
  rtl/m65832_core.vhd \
  tb/tb_m65832_timer.vhd

ghdl -e --std=08 tb_M65832_Timer
ghdl -r --std=08 tb_M65832_Timer --stop-time=1ms
