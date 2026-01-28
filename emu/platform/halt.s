; halt.s - M65832 halt function (assembly)
; Called by sys_exit to stop the processor

    .text
    .globl  _halt
    .type   _halt,@function
_halt:
    STP                 ; Stop processor
    JMP B+_halt         ; Infinite loop (shouldn't reach)
.Lfunc_end_halt:
    .size   _halt, .Lfunc_end_halt-_halt
