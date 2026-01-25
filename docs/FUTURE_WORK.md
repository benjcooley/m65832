## Future Work

### MMIO Timer/Bus Restructure

- The current MMIO timer implementation works within the existing state-machine timing, but it is fragile.
- In a future revision, consider restructuring MMIO reads/writes to latch address/data at the start of
  `ST_READ`/`ST_WRITE` transactions so decode does not depend on cycle-to-cycle ordering of
  `eff_addr`/`data_byte_count`.
- This refactor is a good candidate to fold into any larger core re-architecture (e.g., deeper
  pipelining or more systematic bus timing), where a cleaner transaction boundary is already required.
- Interim mitigation: the core now latches the MMIO base address at the start of `ST_READ`/`ST_WRITE`
  so multi-byte MMIO transactions are more stable, but this does not replace the full restructure.
