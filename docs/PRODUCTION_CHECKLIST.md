## Production Checklist

- [x] Time-sliced interleave scheduler verified against expected tick math
- [x] 6502 coprocessor wiring validated (shared bus + VBR translation)
- [x] IRQ-backed MMIO read path exercised in coprocessor testbench
- [x] Core smoke test added (reset, LDA/STA/JMP)
- [x] Core/MMU suite runnable via `tb/run_core_tests.sh`
- [x] Coprocessor suite runnable via `tb/run_coprocessor_tests.sh`
- [x] Integrate coprocessor IRQ request into system IRQ routing
- [x] Add longer-running soak test with mixed core/coprocessor traffic
