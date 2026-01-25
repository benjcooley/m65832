# Bring-up Checklist (Linux)

## MUST (Linux-blocking)
- [x] Privilege enforcement: trap on privileged ops + user MMIO access  
  Why: prevents user code from corrupting system state or MMU control. (Test 122)
- [x] Exception/interrupt entry/exit contract: push PC + full P, RTI restores both  
  Why: kernel must reliably return to user with exact prior state. (Test 114A)
- [ ] Page faults: precise, with FAULTVA + fault type latched  
  Why: VM subsystem needs exact fault address and cause to resolve faults.  
  Note: Works with focused test, but MMIO FAULTVA read path needs follow-up.
- [ ] TLB invalidate: at least full flush (single-VA optional for v0)  
  Why: page table updates must take effect immediately and safely.
- [ ] Timer interrupt: periodic IRQ + readable counter  
  Why: scheduler, timekeeping, and preemption depend on it.
- [ ] Syscall mechanism: TRAP vector works + return to user  
  Why: user/kernel boundary requires a stable syscall entry point.

## STRONG-SHOULD
- [ ] Cause/EPC registers: EPC + CAUSE (and BADVADDR if separate)  
  Why: makes debugging and kernel exception handling predictable.
- [ ] Illegal instruction exception  
  Why: user bugs and bad code must trap cleanly.
- [ ] Alignment exception (if strict alignment is required)  
  Why: kernel and libc expect defined behavior on misaligned access.
- [ ] Atomic primitives: CAS + LL/SC semantics verified  
  Why: locks and synchronization in Linux depend on correct atomics.
- [ ] Memory barriers: FENCE/FENCER/FENCEW (can be no-ops initially)  
  Why: future-proofing for SMP/caches; compilers assume a fence exists.

## NICE-TO-HAVE
- [ ] ASID optimization (context switch without full flush)  
  Why: reduces TLB churn and speeds multitasking.
- [ ] Exception priority ordering  
  Why: deterministic, spec-aligned behavior under multiple faults.
- [ ] Cache control + uncached MMIO (PCD + flush/invalidate)  
  Why: DMA and device access need reliable cache semantics.
- [ ] Perf counters / TLB hit-miss stats  
  Why: tuning and diagnostics during bring-up.
- [ ] Debug features (breakpoints, single-step)  
  Why: accelerates kernel debugging and toolchain work.

## COMPLEXITY HOTSPOTS (watch for timing/ordering)
- [ ] MMIO read timing (esp. FAULTVA/IRQ vectors)  
- [ ] Exception entry + vector fetch sequencing  
- [ ] MMU/PTW handshakes vs. core state machine  
- [ ] Multi-width accesses (8/16/32/64) and byte-lane ordering
