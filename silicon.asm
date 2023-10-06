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

%define line_buffer_length 8 * 16

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

%macro constant 2
	code_field %1, invoke_constant
		dq %2
%endmacro

%macro variable 2
	constant %1, %%storage
	[section .bss]
		%%storage:
			resq %2

	__?SECT?__
%endmacro

%macro branch_to 1
	dq branch
	dq %1 - %%here

	%%here:
%endmacro

%macro jump_to 1
	dq jump
	dq %1 - %%here

	%%here:
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

	; ( condition -- )
	code branch
		mov rax, [dp]
		add dp, 8
		test rax, rax
		jnz .branch
		add tp, 8
		next

		.branch:
		mov rax, [tp]
		lea tp, [tp + rax + 8]
		next

	; ( a -- (a < 0) )
	code push_is_negative
		cmp qword [dp], 0
		jl .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

	; ( value -- value value )
	code copy
		mov rax, [dp]
		sub dp, 8
		mov [dp], rax
		next

	; ( value -- (value == 0) )
	code push_is_zero
		mov rax, [dp]
		test rax, rax
		jz .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

	; ( -- )
	code jump
		mov rax, [tp]
		lea tp, [tp + rax + 8]
		next

	; ( a -- ~a )
	code push_not
		not qword [dp]
		next

	; ( a b -- (a + b) )
	code push_add
		mov rax, [dp]
		add dp, 8
		add [dp], rax
		next

	; ( address -- byte )
	code load_byte
		mov rax, [dp]
		mov al, [rax]
		movzx rax, al
		mov [dp], rax
		next

	; ( a b -- (a == b) )
	code push_is_eq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jz .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

section .rdata
	; ( -- )
	program:
		dq set_stacks
		dq init_handles

		dq banner
		dq print

		.accept:
		dq accept_line
		branch_to .accept

		dq test_stacks
		dq exit

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

	string status_ok, `[ok]`
	string status_overfull, `[overfull]`
	string status_pending, `                `

	string cursor_up, `\x1bM`
	string newline, `\n`
	variable line_buffer, line_buffer_length / 8

	; ( -- )
	thread new_line
		dq newline
		dq print
		dq return

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
		dq line_size
		dq store
		dq return

	; ( -- continue? )
	thread accept_line
		.again:
		dq status_pending
		dq print
		dq read_line

		dq line_size
		dq load
		dq copy
		dq push_is_zero
		branch_to .empty_line

		dq push_is_negative
		branch_to .eof

		dq is_line_overfull
		branch_to .line_overfull

		dq status_ok
		dq report_status
		dq true
		dq return

		.line_overfull:
		dq status_overfull
		dq report_status

		.flush:
		dq read_line
		dq is_line_overfull
		branch_to .flush
		jump_to .again

		.empty_line:
		dq drop
		dq true
		dq return

		.eof:
		dq zero
		dq return

	constant zero, 0
	constant true, ~0
	constant one, 1
	variable line_size, 1

	; ( string length -- )
	thread report_status
		dq cursor_up
		dq print
		dq print_line
		dq return

	; ( string length -- )
	thread print_line
		dq print
		dq new_line
		dq return

	; ( -- overfull? )
	thread is_line_overfull
		dq line_buffer
		dq line_size
		dq load
		dq one
		dq push_add
		dq push_add
		dq load_byte
		dq literal
		dq `\n`
		dq push_is_eq
		dq push_not
		dq return

	string banner, `\n\n\n\n\n                Silicon (c) 2023 @daviddetweiler\n\n`

section .bss
	data_stack:
		resq stack_depth

	return_stack:
		resq stack_depth
