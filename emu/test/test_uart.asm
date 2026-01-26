; test_uart.asm - Simple UART test program
; Prompts for name and prints greeting
;
; Build: ../../as/m65832as test_uart.asm -o test_uart.bin
; Run:   ../m65832emu --system --raw test_uart.bin

        .org $00100000      ; Load at kernel address
        .m8                 ; 8-bit accumulator
        .x16                ; 16-bit index

; UART registers (32-bit addresses, need WID prefix)
UART_BASE   = $FFFFF100
UART_STATUS = $FFFFF100
UART_TX     = $FFFFF104
UART_RX     = $FFFFF108

; Status bits
TX_READY    = $01
RX_AVAIL    = $02

; Buffer for name input (in low RAM)
NAME_BUF    = $00002000
NAME_MAX    = 64

; Temp pointer storage
PTR_LO      = $00
PTR_HI      = $02

; ============================================================================
; Entry point
; ============================================================================
start:
        ; Print prompt
        lda #<prompt
        sta PTR_LO
        lda #>prompt
        sta PTR_LO+1
        lda #^prompt            ; Bank byte
        sta PTR_LO+2
        lda #0
        sta PTR_LO+3
        jsr print_string

        ; Read name into buffer
        ldx #0                  ; Buffer index
read_loop:
        jsr getchar             ; Get character into A
        cmp #$0D                ; Carriage return?
        beq done_reading
        cmp #$0A                ; Line feed?
        beq done_reading
        cmp #$08                ; Backspace?
        beq handle_bs
        cmp #$7F                ; Delete?
        beq handle_bs
        
        ; Store character and echo
        cpx #NAME_MAX-1         ; Buffer full?
        bcs read_loop           ; Yes, ignore more input
        sta NAME_BUF,x          ; Store in buffer
        inx
        jsr putchar             ; Echo character
        bra read_loop

handle_bs:
        cpx #0                  ; At start of buffer?
        beq read_loop           ; Yes, ignore
        dex                     ; Back up
        lda #$08                ; Send backspace
        jsr putchar
        lda #' '                ; Overwrite with space
        jsr putchar
        lda #$08                ; Backspace again
        jsr putchar
        bra read_loop

done_reading:
        lda #0
        sta NAME_BUF,x          ; Null terminate
        
        ; Print newline
        lda #$0D
        jsr putchar
        lda #$0A
        jsr putchar
        
        ; Print greeting
        lda #<greeting
        sta PTR_LO
        lda #>greeting
        sta PTR_LO+1
        lda #^greeting
        sta PTR_LO+2
        lda #0
        sta PTR_LO+3
        jsr print_string
        
        ; Print name from buffer
        ldx #0
print_name:
        lda NAME_BUF,x
        beq done_name
        jsr putchar
        inx
        bra print_name
        
done_name:
        ; Print exclamation and newline
        lda #'!'
        jsr putchar
        lda #$0D
        jsr putchar
        lda #$0A
        jsr putchar
        
        ; Halt
        stp

; ============================================================================
; putchar - Output character in A to UART
; Preserves all registers except A
; ============================================================================
putchar:
        pha                     ; Save character
putchar_wait:
        wid lda UART_STATUS     ; Check status (32-bit address)
        and #TX_READY           ; TX ready?
        beq putchar_wait        ; No, wait
        pla                     ; Restore character
        wid sta UART_TX         ; Send it (32-bit address)
        rts

; ============================================================================
; getchar - Read character from UART into A
; ============================================================================
getchar:
getchar_wait:
        wid lda UART_STATUS     ; Check status (32-bit address)
        and #RX_AVAIL           ; RX available?
        beq getchar_wait        ; No, wait
        wid lda UART_RX         ; Read character (32-bit address)
        rts

; ============================================================================
; print_string - Print null-terminated string
; String address in PTR_LO (32-bit pointer)
; ============================================================================
print_string:
        phy                     ; Save Y
        ldy #0
print_loop:
        lda [PTR_LO],y          ; Load via indirect long
        beq print_done          ; Null terminator?
        jsr putchar             ; Print it
        iny
        bra print_loop
print_done:
        ply                     ; Restore Y
        rts

; ============================================================================
; Data - placed right after code
; ============================================================================
prompt:
        .byte "What is your name? ", 0

greeting:
        .byte "Hello world ", 0

        .end
