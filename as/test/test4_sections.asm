; Test sections

; Code section
    .SECTION TEXT
    .ORG $4000

    .M16
    .X16

START:
    LDA #0
    LDX #DATA_START
    LDY #DATA_LEN
    
COPY_LOOP:
    LDA $00,X
    STA $1000,Y
    INX
    DEY
    BNE COPY_LOOP
    
    JMP DONE

; Data section
    .SECTION DATA
    .ORG $5000

DATA_START:
    .BYTE $01, $02, $03, $04
    .BYTE $05, $06, $07, $08
DATA_END:

DATA_LEN = DATA_END - DATA_START

; Back to code
    .SECTION TEXT

DONE:
    LDA #$FF
    STA $1000
    RTS

; Read-only data
    .SECTION RODATA
    .ORG $6000

MESSAGE:
    .BYTE "Hello, World!", 0

; BSS section (uninitialized)
    .SECTION BSS
    .ORG $7000

BUFFER:
    .DS 256

COUNTER:
    .DS 4
