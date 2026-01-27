; Generated from LLVM output
; Original: test_add.s

    .org $1000

; === Startup code ===
_start:
    JSR _main          ; Call main function
    LDA R0             ; Load R0 (return value) into A
    STP                ; Stop emulator

; === LLVM generated code ===
_main:                                   ; @main
    LD	R0,#48
    RTS
                                        ; -- End function
