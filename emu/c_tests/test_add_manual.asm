; Manual test: Simple addition
; Expected: A = 0x30 (48)

    .org $1000

; Jump over startup to function, then call it
    JMP B+do_test

do_test:
    ; Call the test function
    JSR B+test_add
    ; Result is in R0, load into A
    LDA R0
    STP

; Test function: returns 16 + 32 = 48
test_add:
    LD R0, #48
    RTS
