## Future Work

### MMIO Timer/Bus Restructure

- The current MMIO timer implementation works within the existing state-machine timing, but it is fragile.
- In a future revision, consider restructuring MMIO reads/writes to latch address/data at the start of
  `ST_READ`/`ST_WRITE` transactions so decode does not depend on cycle-to-cycle ordering of
  `eff_addr`/`data_byte_count`.
- This refactor is a good candidate to fold into any larger core re-architecture (e.g., deeper
  pipelining or more systematic bus timing), where a cleaner transaction boundary is already required.
- MMIO writes currently assert WE on the external bus; this is correct for real hardware where address
  decode selects the target device. If a future simulation memory model does not decode MMIO ranges,
  it may appear to "write through" to RAM at MMIO addresses. If this becomes confusing in tests,
  consider masking MMIO ranges in the testbench memory model rather than changing core WE behavior.
