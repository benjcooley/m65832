#!/bin/sh
set -e

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

base_sources="\
  rtl/m65832_pkg.vhd \
  rtl/m65832_alu.vhd \
  rtl/m65832_regfile.vhd \
  rtl/m65832_addrgen.vhd \
  rtl/m65832_decoder.vhd \
  rtl/m65832_mmu.vhd \
  rtl/m65832_core.vhd"

compile_sources() {
  sources="$1"
  for src in ${sources}; do
    ghdl -a --std=08 "${src}"
  done
}

run_tb() {
  tb_entity="$1"
  stop_time="$2"
  label="$3"
  idx="$4"
  total="$5"
  echo "==> [${idx}/${total}] ${label}"
  ghdl -e --std=08 "${tb_entity}"
  ghdl -r --std=08 "${tb_entity}" --stop-time="${stop_time}"
}

if [ "$#" -eq 0 ]; then
  modules="all"
else
  modules="$*"
fi

case " ${modules} " in
  *" all "*)
    modules="mmu core_smoke core timer coprocessor mx65_illegal interleave coprocessor_soak maincore_timeslice"
    ;;
esac

needs_coprocessor=0
for mod in ${modules}; do
  case "${mod}" in
    coprocessor|mx65_illegal|interleave|coprocessor_soak|maincore_timeslice)
      needs_coprocessor=1
      break
      ;;
  esac
done

sources="${base_sources}"
for mod in ${modules}; do
  case "${mod}" in
    mmu)
      sources="${sources} tb/tb_m65832_mmu.vhd"
      ;;
    core_smoke)
      sources="${sources} tb/tb_m65832_core_smoke.vhd"
      ;;
    core)
      sources="${sources} tb/tb_m65832_core.vhd"
      ;;
    timer)
      sources="${sources} tb/tb_m65832_timer.vhd"
      ;;
    coprocessor|mx65_illegal|interleave|coprocessor_soak|maincore_timeslice)
      sources="${sources} \
        rtl/m65832_interleave.vhd \
        rtl/m65832_shadow_io.vhd \
        cores/6502-mx65/mx65.vhd \
        rtl/m65832_6502_coprocessor.vhd \
        rtl/m65832_coprocessor_top.vhd \
        tb/tb_mx65_illegal.vhd \
        tb/tb_m65832_coprocessor.vhd \
        tb/tb_m65832_interleave.vhd \
        tb/tb_m65832_coprocessor_soak.vhd \
        tb/tb_m65832_maincore_timeslice.vhd"
      ;;
  esac
done

compile_sources "${sources}"

total=0
for mod in ${modules}; do
  total=$((total + 1))
done

idx=0
for mod in ${modules}; do
  idx=$((idx + 1))
  case "${mod}" in
    mmu)
      run_tb tb_M65832_MMU 1ms "MMU" "${idx}" "${total}"
      ;;
    core_smoke)
      run_tb tb_M65832_Core_Smoke 2ms "Core smoke" "${idx}" "${total}"
      ;;
    core)
      run_tb tb_M65832_Core 1ms "Core" "${idx}" "${total}"
      ;;
    timer)
      run_tb tb_M65832_Timer 1ms "Timer" "${idx}" "${total}"
      ;;
    coprocessor)
      run_tb tb_M65832_Coprocessor 3ms "Coprocessor" "${idx}" "${total}"
      ;;
    mx65_illegal)
      run_tb tb_MX65_Illegal 3ms "MX65 illegal" "${idx}" "${total}"
      ;;
    interleave)
      run_tb tb_M65832_Interleave 2us "Interleave" "${idx}" "${total}"
      ;;
    coprocessor_soak)
      run_tb tb_M65832_Coprocessor_Soak 10ms "Coprocessor soak" "${idx}" "${total}"
      ;;
    maincore_timeslice)
      run_tb tb_M65832_Maincore_Timeslice 5ms "Maincore timeslice" "${idx}" "${total}"
      ;;
    *)
      echo "Unknown module: ${mod}"
      exit 1
      ;;
  esac
done
