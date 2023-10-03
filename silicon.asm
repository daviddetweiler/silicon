default rel
bits 64

global start

extern ExitProcess

%define tp r15
%define wp r14
%define dp r13
%define rp r12

%define stack_depth 32
%define stack_base(stack) (stack + stack_depth * 8)

%macro run 0
    jmp [wp]
%endmacro

%macro next 0
    mov wp, [tp]
    add tp, 8
    run
%endmacro

%macro code_field 2
    align 8
    %1:
        dq %2
%endmacro

%macro code 1
    code_field %1, %%here
        %%here:
%endmacro

%macro thread 1
    code_field %1, invoke_thread
%endmacro

section .text
    ; ( -- )
    start:
        sub rsp, 8 + 8 * 16 ; enough room for 16 parameters, plus stack alignment
        lea tp, program
        next

    ; ( -- )
    code exit
        xor rcx, rcx
        call ExitProcess

    ; ( -- )
    code set_stacks
        lea dp, stack_base(data_stack)
        lea rp, stack_base(return_stack)
        next

    ; ( -- )
    code test_stacks
        lea rax, stack_base(data_stack)
        cmp dp, rax
        jne .stack_error
        lea rax, stack_base(return_stack)
        cmp rp, rax
        jne .stack_error
        next

        .stack_error:
        int3
        next

    ; ( -- )
    invoke_thread:
        sub rp, 8
        mov [rp], tp
        lea tp, [wp + 8]
        next

    ; ( value -- )
    code drop
        add dp, 8
        next

    ; ( -- value )
    code literal
        mov rax, [tp]
        add tp, 8
        sub dp, 8
        mov [dp], rax
        next

    ; ( -- )
    code return
        mov tp, [rp]
        add rp, 8
        next

section .rdata
    ; ( -- )
    program:
        dq set_stacks
        dq self_test
        dq test_stacks
        dq exit

    ; ( -- )
    thread self_test
        dq literal
        dq 0
        dq drop
        dq return

section .bss
    data_stack:
        resq stack_depth

    return_stack:
        resq stack_depth
