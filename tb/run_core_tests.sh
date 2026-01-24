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
  tb/tb_m65832_mmu.vhd \
  tb/tb_m65832_core.vhd \
  tb/tb_m65832_core_smoke.vhd

ghdl -e --std=08 tb_M65832_MMU
ghdl -r --std=08 tb_M65832_MMU --stop-time=1ms

ghdl -e --std=08 tb_M65832_Core_Smoke
ghdl -r --std=08 tb_M65832_Core_Smoke --stop-time=2ms

ghdl -e --std=08 tb_M65832_Core
ghdl -r --std=08 tb_M65832_Core --stop-time=1ms
