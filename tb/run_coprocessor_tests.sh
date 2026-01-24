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
  rtl/m65832_6502_coprocessor.vhd \
  rtl/m65832_coprocessor_top.vhd \
  tb/tb_m65832_coprocessor.vhd

ghdl -e --std=08 tb_M65832_Coprocessor
ghdl -r --std=08 tb_M65832_Coprocessor --stop-time=3ms
