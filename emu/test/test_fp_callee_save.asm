; Test: FP register (F14) callee-save via STF.S / LDF.S
;
; Verifies that F14 can be correctly saved to a memory frame slot and
; restored from it — the mechanism LLVM uses via storeRegToStackSlot /
; loadRegFromStackSlot when F14 is a callee-saved register.
;
; Without the fix in M65832FrameLowering.cpp, the old LDA_DP+PHA path
; would compute a garbage DP offset for F14 (non-GPR register), silently
; save the wrong memory location, and F14 would be corrupted after any
; function call.
;
; Expected result: A = $0000000E (14)

    .ORG $1000
    .M32
    .X32

    ; Enter 32-bit native mode (W=00 -> W=11)
    SEPE #$03

    ; Set D=0 so DP offsets $00,$04,... map to physical addresses 0,4,...
    ; R=0 (register window off): DP access reads R0 pointer from mem[D+0*4]=mem[0]
    LDA #$00000000
    TCD

    ; Load F14 = 14.0 — the value that must survive the callee save/restore
    LDA #$0000000E
    I2F.S F14          ; F14 = 14.0

    ; Point R0 at the frame slot address ($00002000)
    ; With D=0 and R=0, STA $00 writes to mem[0], which is where LDF.S/STF.S
    ; read R0 from (mem[D + rm*4] = mem[0 + 0*4] = mem[0]).
    LDA #$00002000
    STA $00            ; R0 = $00002000

    ; Save F14 to the frame slot (mirrors storeRegToStackSlot for F14)
    STF.S F14, (R0)    ; mem[$2000] = F14 bits (14.0)

    ; Clobber F14 with a different value to prove restoration works
    LDA #$00000063     ; 99
    I2F.S F14          ; F14 = 99.0  (intentionally wrong)

    ; Restore F14 from the frame slot (mirrors loadRegFromStackSlot for F14)
    LDF.S F14, (R0)    ; F14 = mem[$2000] (should restore 14.0)

    ; Convert back to integer and verify — A must equal 14
    F2I.S F14          ; A = (int)F14 = 14 = $0000000E
    STP
