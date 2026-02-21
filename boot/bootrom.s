; M65832 Boot ROM
;
; Minimal boot ROM that:
;   1. Initializes CPU (native 32-bit, supervisor)
;   2. Prints "M65832\r\n" banner on UART
;   3. Reads boot header from sector 0 via block device DMA
;   4. Reads kernel from disk into RAM at load address
;   5. Writes boot_params at 0x1000
;   6. Jumps to kernel entry point
;
; Assembled with: m65832as bootrom.s -o bootrom.bin
; ROM is placed at 0xFFFF0000 (4KB)

; ============================================================================
; Platform register constants (match platform_de25.h / blkdev.h)
; ============================================================================

; Block device registers (base = 0x1000A000)
BLKDEV_BASE     .EQU $1000A000
BLKDEV_CTRL     .EQU $00        ; Command register (W)
BLKDEV_STATUS   .EQU $04        ; Status register (R)
BLKDEV_SECTOR   .EQU $0C        ; Sector number low (R/W)
BLKDEV_COUNT    .EQU $28        ; Block count (R/W)
BLKDEV_DMA      .EQU $38        ; DMA address (R/W)

; Block device commands
CMD_READ        .EQU $01

; Block device status bits
STATUS_READY    .EQU $02

; UART registers (base = 0x10006000)
UART_BASE       .EQU $10006000
UART_DATA       .EQU $00        ; TX/RX data
UART_STATUS     .EQU $04        ; Status register
UART_TX_READY   .EQU $02        ; TX ready bit

; Boot header constants
BOOT_MAGIC      .EQU $4236354D  ; "M65B" little-endian
BOOT_PARAMS_ADDR .EQU $00001000 ; Boot params address in RAM
BP_MAGIC        .EQU $4D363538  ; boot_params magic "M658"

; Scratch RAM for boot header read
SCRATCH         .EQU $00002000

; ============================================================================
; Boot ROM code (placed at 0xFFFF0000)
; ============================================================================

    .ORG $FFFF0000
    .M32
    .X32

reset_entry:
    ; -------------------------------------------
    ; Step 1: CPU initialization
    ; -------------------------------------------
    ; Single instruction: set W0+W1 (32-bit) + S (supervisor) + R (register window)
    SEPE #$1B                   ; W0|W1|S|R -> 32-bit, supervisor, register window
    SEI                         ; Disable interrupts

    ; Set stack pointer
    LDA #$0000FFFF
    TCS                         ; SP = 0x0000FFFF

    ; -------------------------------------------
    ; Step 2: Print UART banner "M65832\r\n"
    ; -------------------------------------------
    LDA #$4D                    ; 'M'
    JSR putc
    LDA #$36                    ; '6'
    JSR putc
    LDA #$35                    ; '5'
    JSR putc
    LDA #$38                    ; '8'
    JSR putc
    LDA #$33                    ; '3'
    JSR putc
    LDA #$32                    ; '2'
    JSR putc
    LDA #$0D                    ; CR
    JSR putc
    LDA #$0A                    ; LF
    JSR putc

    ; -------------------------------------------
    ; Step 3: Read boot header (sector 0) via DMA
    ; -------------------------------------------

    ; Set DMA destination: scratch RAM at 0x2000
    LDA #SCRATCH
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_DMA
    STA R9
    LDA R8
    STA (R9)

    ; Set sector number: 0
    LDA #0
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_SECTOR
    STA R9
    LDA R8
    STA (R9)

    ; Set count: 1 sector
    LDA #1
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_COUNT
    STA R9
    LDA R8
    STA (R9)

    ; Issue read command
    LDA #CMD_READ
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_CTRL
    STA R9
    LDA R8
    STA (R9)

    ; Wait for ready
    JSR wait_blkdev

    ; -------------------------------------------
    ; Step 4: Parse boot header and validate magic
    ; -------------------------------------------

    ; Read magic from scratch+0
    LDA #SCRATCH
    STA R9
    LDA (R9)                    ; A = magic at SCRATCH+0
    STA R0                      ; R0 = magic

    ; Compare with expected magic
    LDA #BOOT_MAGIC
    CMP R0                      ; Compare A with R0 (DP $00)
    BNE boot_error              ; Magic mismatch

    ; Read kernel_sector from scratch+8
    LDA #SCRATCH + 8
    STA R9
    LDA (R9)
    STA R2                      ; R2 = kernel_sector

    ; Read kernel_size from scratch+12
    LDA #SCRATCH + 12
    STA R9
    LDA (R9)
    STA R3                      ; R3 = kernel_size

    ; Read kernel_load_addr from scratch+16
    LDA #SCRATCH + 16
    STA R9
    LDA (R9)
    STA R4                      ; R4 = kernel_load_addr

    ; Read kernel_entry_offset from scratch+20
    LDA #SCRATCH + 20
    STA R9
    LDA (R9)
    STA R5                      ; R5 = kernel_entry_offset

    ; -------------------------------------------
    ; Step 5: Load kernel from disk
    ; -------------------------------------------

    ; Calculate sector count: (kernel_size + 511) / 512
    LDA R3                      ; A = kernel_size
    CLC
    ADC #511
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA R6                      ; R6 = sector count

    ; Set DMA destination: kernel_load_addr
    LDA R4
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_DMA
    STA R9
    LDA R8
    STA (R9)

    ; Set sector number: kernel_sector
    LDA R2
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_SECTOR
    STA R9
    LDA R8
    STA (R9)

    ; Set count: sector_count
    LDA R6
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_COUNT
    STA R9
    LDA R8
    STA (R9)

    ; Issue read command
    LDA #CMD_READ
    STA R8
    LDA #BLKDEV_BASE + BLKDEV_CTRL
    STA R9
    LDA R8
    STA (R9)

    ; Wait for ready
    JSR wait_blkdev

    ; Print "Kernel loaded\r\n"
    JSR print_kernel_loaded

    ; Signal debugger: kernel image loaded, re-apply breakpoints
    .BYTE $42, $01              ; WDM #$01 (raw bytes, not valid in 32-bit asm)

    ; -------------------------------------------
    ; Step 6: Write boot_params at 0x1000
    ; -------------------------------------------

    ; boot_params.magic = BOOT_PARAMS_MAGIC (0x4D363538 = "M658")
    LDA #BP_MAGIC
    STA R8
    LDA #BOOT_PARAMS_ADDR
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[0] = magic

    ; boot_params.version = 1
    LDA #1
    STA R8
    LDA #BOOT_PARAMS_ADDR + 4
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[4] = version

    ; boot_params.mem_base = 0
    LDA #0
    STA R8
    LDA #BOOT_PARAMS_ADDR + 8
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[8] = mem_base

    ; boot_params.mem_size = 0x10000000 (256MB)
    LDA #$10000000
    STA R8
    LDA #BOOT_PARAMS_ADDR + 12
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[12] = mem_size

    ; boot_params.kernel_start = kernel_load_addr
    LDA R4
    STA R8
    LDA #BOOT_PARAMS_ADDR + 16
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[16] = kernel_start

    ; boot_params.kernel_size = kernel_size
    LDA R3
    STA R8
    LDA #BOOT_PARAMS_ADDR + 20
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[20] = kernel_size

    ; boot_params.uart_base = UART_BASE
    LDA #UART_BASE
    STA R8
    LDA #BOOT_PARAMS_ADDR + 40
    STA R9
    LDA R8
    STA (R9)                    ; boot_params[40] = uart_base

    ; -------------------------------------------
    ; Step 7: Jump to kernel
    ; -------------------------------------------

    ; Entry = kernel_load_addr + kernel_entry_offset
    LDA R4                      ; kernel_load_addr
    CLC
    ADC R5                      ; + entry_offset
    STA R8                      ; R8 = entry point

    ; Print "Booting...\r\n" (putc preserves R8/R9)
    JSR print_booting

    ; Pass boot_params pointer in R0
    LDA #BOOT_PARAMS_ADDR
    STA R0

    ; Jump to kernel
    JMP (R8)

; ============================================================================
; Subroutines
; ============================================================================

; putc -- Send character in A to UART (polled)
;   Preserves all registers (A, R8, R9)
putc:
    PHA                         ; [SP+9] Save character
    LDA R8
    PHA                         ; [SP+5] Save R8
    LDA R9
    PHA                         ; [SP+1] Save R9
putc_wait:
    LDA #UART_BASE + UART_STATUS
    STA R9
    LDA (R9)                    ; Read UART status
    AND #UART_TX_READY
    BEQ putc_wait               ; Loop until TX ready
    LDA $09,S                   ; Load character from stack
    STA R8
    LDA #UART_BASE + UART_DATA
    STA R9
    LDA R8
    STA (R9)                    ; Write character to UART TX
    PLA
    STA R9                      ; Restore R9
    PLA
    STA R8                      ; Restore R8
    PLA                         ; Discard saved character
    RTS

; wait_blkdev -- Wait for block device READY status
wait_blkdev:
blkdev_poll:
    LDA #BLKDEV_BASE + BLKDEV_STATUS
    STA R9
    LDA (R9)                    ; Read status
    AND #STATUS_READY
    BEQ blkdev_poll             ; Loop until READY
    RTS

; print_kernel_loaded -- Print "Kernel loaded\r\n"
print_kernel_loaded:
    LDA #$4B ; 'K'
    JSR putc
    LDA #$65 ; 'e'
    JSR putc
    LDA #$72 ; 'r'
    JSR putc
    LDA #$6E ; 'n'
    JSR putc
    LDA #$65 ; 'e'
    JSR putc
    LDA #$6C ; 'l'
    JSR putc
    LDA #$20 ; ' '
    JSR putc
    LDA #$6C ; 'l'
    JSR putc
    LDA #$6F ; 'o'
    JSR putc
    LDA #$61 ; 'a'
    JSR putc
    LDA #$64 ; 'd'
    JSR putc
    LDA #$65 ; 'e'
    JSR putc
    LDA #$64 ; 'd'
    JSR putc
    LDA #$0D
    JSR putc
    LDA #$0A
    JSR putc
    RTS

; print_booting -- Print "Booting...\r\n"
print_booting:
    LDA #$42 ; 'B'
    JSR putc
    LDA #$6F ; 'o'
    JSR putc
    LDA #$6F ; 'o'
    JSR putc
    LDA #$74 ; 't'
    JSR putc
    LDA #$69 ; 'i'
    JSR putc
    LDA #$6E ; 'n'
    JSR putc
    LDA #$67 ; 'g'
    JSR putc
    LDA #$2E ; '.'
    JSR putc
    LDA #$2E ; '.'
    JSR putc
    LDA #$2E ; '.'
    JSR putc
    LDA #$0D
    JSR putc
    LDA #$0A
    JSR putc
    RTS

; boot_error -- Print "ERR\r\n" and halt
boot_error:
    LDA #$45                    ; 'E'
    JSR putc
    LDA #$52                    ; 'R'
    JSR putc
    LDA #$52                    ; 'R'
    JSR putc
    LDA #$0D
    JSR putc
    LDA #$0A
    JSR putc
err_halt:
    WAI
    BRA err_halt

; ============================================================================
; Reset vector (at ROM offset 0xFFC)
; ============================================================================

    .ORG $FFFF0FFC
    .LONG $FFFF0000             ; Reset vector -> ROM base
