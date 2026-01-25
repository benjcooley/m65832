; Test expressions
    .ORG $6000

; Constants
BASE = $1000
OFFSET = $20
COUNT = 10

; Arithmetic
ADD_TEST = BASE + OFFSET      ; $1020
SUB_TEST = BASE - $100        ; $0F00
MUL_TEST = COUNT * 4          ; 40 = $28
DIV_TEST = $100 / 16          ; 16 = $10
MOD_TEST = 17 % 5             ; 2

; Bitwise
AND_TEST = $FF & $0F          ; $0F
OR_TEST  = $F0 | $0F          ; $FF
XOR_TEST = $FF ^ $AA          ; $55

; Parentheses
PAREN1 = (1 + 2) * 3          ; 9
PAREN2 = 10 + (5 * 2)         ; 20
PAREN3 = ((2 + 2) * (3 + 3))  ; 24
COMPLEX = (BASE + (OFFSET * 2)) / 4  ; ($1000 + $40) / 4 = $410

; Unary operators
NEG_TEST = -1                 ; $FFFFFFFF
LOW_BYTE = <$1234             ; $34
HIGH_BYTE = >$1234            ; $12
BANK_BYTE = ^$123456          ; $12

; PC-relative
PC_START = *
    NOP                       ; 1 byte
    NOP                       ; 1 byte
PC_DIFF = * - PC_START        ; Should be 2

; Character constants
CHAR_A = 'A'                  ; 65 = $41
CHAR_NL = '\n'                ; 10 = $0A

; Output test values
    .BYTE <ADD_TEST, >ADD_TEST                   ; $20, $10
    .BYTE MUL_TEST                               ; $28
    .BYTE DIV_TEST                               ; $10
    .BYTE MOD_TEST                               ; $02
    .BYTE AND_TEST                               ; $0F
    .BYTE OR_TEST                                ; $FF
    .BYTE XOR_TEST                               ; $55
    .BYTE PAREN1                                 ; $09
    .BYTE PAREN2                                 ; $14
    .BYTE PAREN3                                 ; $18
    .BYTE LOW_BYTE                               ; $34
    .BYTE HIGH_BYTE                              ; $12
    .BYTE BANK_BYTE                              ; $12
    .BYTE PC_DIFF                                ; $02
    .BYTE CHAR_A                                 ; $41
