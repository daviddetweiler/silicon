default rel
bits 64

global start

extern ExitProcess
extern WriteFile
extern GetStdHandle
extern ReadFile

%define tp r15
%define wp r14
%define dp r13
%define rp r12

%define stack_depth 32
%define stack_base(stack) (stack + stack_depth * 8)

%define line_buffer_length 256

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

%macro string 2
    code_field %1, invoke_string
        db %strlen(%2), %2
%endmacro

%macro variable 2
    code_field %1, invoke_constant
        dq %%storage

    [section .bss]
        %%storage:
            resq %2

    __?SECT?__
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

    ; ( -- string length )
    invoke_string:
        sub dp, 8 * 2
        mov al, [wp + 8]
        movzx rax, al
        mov [dp], rax
        lea rbx, [wp + 9]
        mov [dp + 8], rbx
        next

    ; ( string length handle -- succeeded )
    code write_file
        mov rcx, [dp]
        mov rdx, [dp + 8 * 2]
        mov r8, [dp + 8]
        lea r9, [rsp + 8 * 5]
        mov qword [rsp + 8 * 4], 0
        call WriteFile
        add dp, 8 * 2
        mov [dp], rax
        next

    ; ( -- constant )
    invoke_constant:
        mov rax, [wp + 8]
        sub dp, 8
        mov [dp], rax
        next

    ; ( address -- value )
    code load
        mov rax, [dp]
        mov rax, [rax]
        mov [dp], rax
        next

    ; ( value address -- )
    code store
        mov rax, [dp]
        mov rbx, [dp + 8]
        mov [rax], rbx
        add dp, 8 * 2
        next

    ; ( id -- handle )
    code get_handle
        mov rcx, [dp]
        call GetStdHandle
        mov [dp], rax
        next

    ; ( buffer length handle -- count succeeded )
    code read_file
        mov rcx, [dp]
        mov rdx, [dp + 8 * 2]
        mov r8, [dp + 8]
        lea r9, [dp + 8 * 2]
        xor rax, rax
        mov [r9], rax
        mov qword [rsp + 8 * 4], rax
        call ReadFile
        add dp, 8
        mov [dp], rax
        next

    ; ( a b -- (a - b) )
    code push_subtract
        mov rax, [dp]
        add dp, 8
        sub [dp], rax
        next

section .rdata
    ; ( -- )
    program:
        dq set_stacks
        dq self_test
        dq init_handles        
        dq accept_line
        dq test_stacks
        dq exit

    ; ( -- )
    thread self_test
        dq literal
        dq 0
        dq drop
        dq return

    ; ( string length -- )
    thread print
        dq stdout_handle
        dq load
        dq write_file
        dq drop
        dq return

    variable stdin_handle, 1
    variable stdout_handle, 1

    ; ( -- )
    thread init_handles
        dq literal
        dq -10
        dq get_handle
        dq stdin_handle
        dq store

        dq literal
        dq -11
        dq get_handle
        dq stdout_handle
        dq store

        dq return

    string ok, ` (ok)\n`
    string cursor_up, `\x1bM`
    variable line_buffer, line_buffer_length

    ; ( -- count )
    thread read_line
        dq line_buffer
        dq literal
        dq line_buffer_length
        dq stdin_handle
        dq load
        dq read_file
        dq drop
        dq literal
        dq 2
        dq push_subtract
        dq return

    ; ( -- )
    thread accept_line
        dq line_buffer
        dq read_line
        dq cursor_up
        dq print
        dq print
        dq ok
        dq print
        dq return

section .bss
    data_stack:
        resq stack_depth

    return_stack:
        resq stack_depth
