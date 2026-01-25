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
  rtl/m65832_interleave.vhd \
  rtl/m65832_shadow_io.vhd \
  cores/6502-mx65/mx65.vhd \
  tb/tb_mx65_illegal.vhd \
  rtl/m65832_6502_coprocessor.vhd \
  rtl/m65832_coprocessor_top.vhd \
  tb/tb_m65832_coprocessor.vhd \
  tb/tb_m65832_interleave.vhd \
  tb/tb_m65832_coprocessor_soak.vhd \
  tb/tb_m65832_maincore_timeslice.vhd

ghdl -e --std=08 tb_M65832_Coprocessor
ghdl -r --std=08 tb_M65832_Coprocessor --stop-time=3ms

ghdl -e --std=08 tb_MX65_Illegal
ghdl -r --std=08 tb_MX65_Illegal --stop-time=3ms

ghdl -e --std=08 tb_M65832_Interleave
ghdl -r --std=08 tb_M65832_Interleave --stop-time=2us

ghdl -e --std=08 tb_M65832_Coprocessor_Soak
ghdl -r --std=08 tb_M65832_Coprocessor_Soak --stop-time=10ms

ghdl -e --std=08 tb_M65832_Maincore_Timeslice
ghdl -r --std=08 tb_M65832_Maincore_Timeslice --stop-time=5ms
