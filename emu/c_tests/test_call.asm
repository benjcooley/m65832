; Generated from LLVM output
; Original: test_call.s

    .org $1000

; === Startup code ===
_start:
    JSR _main          ; Call main function
    LDA R0             ; Load R0 (return value) into A
    STP                ; Stop emulator

; === LLVM generated code ===
add5:                                   ; @add5
    ADD	R0,#5
    RTS
                                        ; -- End function
_main:                                   ; @main
    LD	R0,#10
    JSR B+B+add5
    RTS
                                        ; -- End function
