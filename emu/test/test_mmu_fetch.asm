; test_mmu_fetch.asm - Test MMU instruction fetch translation
;
; Tests that after enabling the MMU with an identity + high mapping,
; instruction fetch works at virtual addresses.
;
; Memory layout:
;   0x1000: This test code (physical, identity mapped)
;   Page tables at 0x4000 (PGD) and 0x6000 (PTE)
;   Identity map: virtual 0x0 -> physical 0x0
;   High map: virtual 0x80000000 -> physical 0x0
;
; After MMU enable, jumps to virtual 0x80001080 which maps to
; physical 0x1080 where we place a small success routine.
;
; Expected result: A = 42 (0x2A) on success

    .ORG $1000

start:
    SEI
    
    ; --- Set up page tables ---
    ; Clear PGD at $4000 (8KB = 1024 x 8 bytes)
    LDA #$4000
    STA R0
    LDA #$6000
    STA R1
.clear_pgd:
    LDA R0
    CMP R1
    BCS .pgd_done
    LDA #0
    STA (R0)
    LDA R0
    CLC
    ADC #4
    STA R0
    BRA .clear_pgd
.pgd_done:

    ; Clear PTE at $6000 (8KB)
    LDA #$6000
    STA R0
    LDA #$8000
    STA R1
.clear_pte:
    LDA R0
    CMP R1
    BCS .pte_done
    LDA #0
    STA (R0)
    LDA R0
    CLC
    ADC #4
    STA R0
    BRA .clear_pte
.pte_done:

    ; PGD[0] = PTE table ($6000) | Present | Writable
    ; PGD entry 0 at offset 0*8 = $4000
    LDA #$4000
    STA R9
    LDA #$6003          ; $6000 | 3
    STA (R9)
    LDA R9
    CLC
    ADC #4
    STA R9
    LDA #0
    STA (R9)            ; High 32 = 0

    ; PGD[512] = same PTE table | Present | Writable
    ; PGD entry 512 at offset 512*8 = $4000 + $1000 = $5000
    LDA #$5000
    STA R9
    LDA #$6003
    STA (R9)
    LDA R9
    CLC
    ADC #4
    STA R9
    LDA #0
    STA (R9)

    ; Fill PTE[0] = $0003 (physical page 0 | P | W)
    ; This maps virtual 0x0000_0xxx -> physical 0x0000_0xxx
    ; and virtual 0x8000_0xxx -> physical 0x0000_0xxx
    LDA #$6000
    STA R9
    LDA #$0003          ; Physical page 0 | P | W
    STA (R9)
    LDA R9
    CLC
    ADC #4
    STA R9
    LDA #0
    STA (R9)

    ; Fill PTE[1] = $1003 (physical page $1000 | P | W)
    ; Maps virtual 0x0000_1xxx -> physical 0x0000_1xxx
    ; and virtual 0x8000_1xxx -> physical 0x0000_1xxx
    LDA #$6008
    STA R9
    LDA #$1003          ; Physical page $1000 | P | W
    STA (R9)
    LDA R9
    CLC
    ADC #4
    STA R9
    LDA #0
    STA (R9)

    ; --- Set PTBR ---
    LDA #$FFFFF014
    STA R8
    LDA #$4000
    STA (R8)            ; PTBR_LO = $4000
    LDA #$FFFFF018
    STA R8
    LDA #0
    STA (R8)            ; PTBR_HI = 0

    ; --- Enable MMU ---
    LDA #$FFFFF000
    STA R8
    LDA #1
    STA (R8)            ; MMUCR = 1 (paging on)

    ; --- Still running at physical address (identity mapped) ---
    ; Jump to virtual address 0x80001080
    ; This should translate to physical 0x1080 via PGD[512]->PTE[1]
    LDA #$80001080
    STA R8
    JMP (R8)

    ; Should not reach here
    LDA #$FF
    STP

    ; --- Success routine at physical $1080 ---
    ; Virtual address 0x80001080 maps here via kernel mapping
    .ORG $1080
success:
    LDA #42             ; Success: A = 42
    STP
