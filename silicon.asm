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

%define immediate 0x80
%define entry_0 0

%assign dictionary_written 0
%assign dictionary_head 0

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
	[section .rdata]
		code_field %1, %%here

	__?SECT?__
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

%macro predicated 2
	dq predicate
	dq %1
	dq %2
%endmacro

%define dictionary_entry(id) entry_ %+ id

%macro declare 1-2 0
	%push

	%if dictionary_written
		%error "Cannot declare words after dictionary has been written"
	%elif %strlen(%1) >= 0x80
		%error "Word name too long"
	%endif

	%assign n dictionary_head + 1

	[section .rdata]
		dictionary_entry(n):
			dq dictionary_entry(dictionary_head)
			db %strlen(%1) | %2, %1, 0

	__?SECT?__

	%assign dictionary_head n

	%pop
%endmacro

%macro commit_dictionary 0
	section .rdata
		declare "core-vocabulary"
		constant core_vocabulary, entry_ %+ dictionary_head
		%assign dictionary_written 1
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
	declare "drop"
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
	declare "write-file"
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
	declare "load"
	code load
		mov rax, [dp]
		mov rax, [rax]
		mov [dp], rax
		next

	; ( value address -- )
	declare "store"
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
	declare "read-file"
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
	declare "-"
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
	declare "0>"
	code push_is_negative
		cmp qword [dp], 0
		jl .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

	; ( value -- value value )
	declare "copy"
	code copy
		mov rax, [dp]
		sub dp, 8
		mov [dp], rax
		next

	; ( value -- (value == 0) )
	declare "0="
	code push_is_zero
		mov rax, [dp]
		test rax, rax
		jz .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

	; ( value -- (value != 0) )
	declare "0~="
	code push_is_nzero
		mov rax, [dp]
		test rax, rax
		jnz .true
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

	; ( a b -- (a + b) )
	declare "+"
	code push_add
		mov rax, [dp]
		add dp, 8
		add [dp], rax
		next

	; ( address -- byte )
	declare "load-byte"
	code load_byte
		mov rax, [dp]
		mov al, [rax]
		movzx rax, al
		mov [dp], rax
		next

	; ( a b -- (a != b) )
	declare "~="
	code push_is_neq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jne .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

	; ( a b -- (a == b) )
	declare "="
	code push_is_eq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		je .true
		mov qword [dp], 0
		next

		.true:
		mov qword [dp], ~0
		next

	; ( value -- )
	declare "stash"
	code stash
		mov rax, [dp]
		add dp, 8
		sub rp, 8
		mov [rp], rax
		next

	; ( -- value )
	declare "unstash"
	code unstash
		mov rax, [rp]
		add rp, 8
		sub dp, 8
		mov [dp], rax
		next

	; ( a b -- b a )
	declare "swap"
	code swap
		mov rax, [dp]
		xchg rax, [dp + 8]
		mov [dp], rax
		next

	; ( a b -- a b a b )
	declare "copy-pair"
	code copy_pair
		mov rax, [dp]
		mov rbx, [dp + 8]
		sub dp, 8 * 2
		mov [dp], rax
		mov [dp + 8], rbx
		next

	; ( a b -- b )
	declare "nip"
	code nip
		mov rax, [dp]
		add dp, 8
		mov [dp], rax
		next

	; ( a b -- a b a )
	declare "over"
	code over
		mov rax, [dp + 8]
		sub dp, 8
		mov [dp], rax
		next

	; ( value address -- )
	declare "store-byte"
	code store_byte
		mov rax, [dp]
		mov rbx, [dp + 8]
		mov [rax], bl
		add dp, 8 * 2
		next

	; ( a -- ~a )
	declare "~"
	code push_not
		not qword [dp]
		next

	; ( a b -- (a & b) )
	declare "&"
	code push_and
		mov rax, [dp]
		add dp, 8
		and [dp], rax
		next

	; ( condition -- )
	code predicate
		mov rax, [tp]
		mov rbx, [tp + 8]
		add tp, 8 * 2
		mov rcx, [dp]
		add dp, 8
		test rcx, rcx
		jnz .true
		mov wp, rbx
		run

		.true:
		mov wp, rax
		run


section .rdata
	; ( -- )
	program:
		dq set_stacks
		dq init_handles
		dq init_current_word
		dq init_dictionary

		dq information

		.accept:
		dq accept_word
		branch_to .exit
		dq current_word
		dq print_line
		jump_to .accept

		.exit:
		dq test_stacks
		dq exit

	; ( string length -- )
	declare "print"
	thread print
		dq stdout_handle
		dq load
		dq write_file
		dq drop
		dq return

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

	; ( -- )
	declare "nl"
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
		dq zero
		dq over
		dq line_buffer
		dq push_add
		dq store_byte
		dq literal
		dq 2
		dq push_subtract
		dq line_size
		dq store
		dq return

	; ( -- exit? )
	thread accept_line
		.again:
		dq read_line

		dq line_size
		dq load

		dq copy
		dq push_is_negative
		branch_to .eof

		dq push_is_zero
		branch_to .again

		dq is_line_overfull
		branch_to .line_overfull

		dq zero
		dq return

		.line_overfull:
		dq status_overfull
		dq print_line

		.flush:
		dq read_line
		dq is_line_overfull
		branch_to .flush
		jump_to .again

		.eof:
		dq drop
		dq true
		dq return

	; ( string length -- )
	declare "print-line"
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
		dq push_is_neq
		dq return

	; ( -- line length )
	thread current_line
		dq line_buffer
		dq line_size
		dq load
		dq return

	; ( -- exit? )
	thread accept_word
		.again:
		dq current_word
		dq push_add
		dq copy

		dq line_buffer
		dq push_subtract
		dq line_size
		dq load
		dq push_is_eq
		branch_to .refill

		dq consume_space
		dq copy
		dq load_byte
		dq push_is_zero
		branch_to .refill
		dq copy
		dq consume_word
		dq copy_pair
		dq swap
		dq push_subtract
		dq nip

		dq current_word_pair
		dq store_pair
		dq zero
		dq return

		.refill:
		dq drop
		dq accept_line
		branch_to .exit
		dq init_current_word
		jump_to .again

		.exit:
		dq true
		dq return

	; ( a b address -- )
	declare "store-pair"
	thread store_pair
		dq copy
		dq stash
		dq cell_size
		dq push_add
		dq store
		dq unstash
		dq store
		dq return

	; ( address -- a b )
	declare "load-pair"
	thread load_pair
		dq copy
		dq cell_size
		dq push_add
		dq stash
		dq load
		dq unstash
		dq load
		dq return

	; ( -- word length )
	thread current_word
		dq current_word_pair
		dq load_pair
		dq return

	; ( -- )
	thread init_current_word
		dq line_buffer
		dq zero
		dq current_word_pair
		dq store_pair
		dq return

	; ( ptr -- new_ptr )
	thread consume_space
		.again:
		dq copy
		dq load_byte
		dq is_space
		branch_to .advance
		dq return

		.advance:
		dq one
		dq push_add
		jump_to .again

	; ( ptr -- new_ptr )
	thread consume_word
		.again:
		dq copy
		dq load_byte
		dq copy
		dq push_is_zero
		branch_to .return
		dq copy
		dq is_space
		branch_to .return
		dq drop
		dq one
		dq push_add
		jump_to .again

		.return:
		dq drop
		dq return

	; ( char -- space? )
	thread is_space
		dq copy
		dq literal
		dq ` `
		dq push_is_eq
		branch_to .true

		dq copy
		dq literal
		dq `\t`
		dq push_is_eq
		branch_to .true

		dq copy
		dq literal
		dq `\r`
		dq push_is_eq
		branch_to .true

		dq copy
		dq literal
		dq `\n`
		dq push_is_eq
		branch_to .true

		dq drop
		dq zero
		dq return

		.true:
		dq drop
		dq true
		dq return

	; ( -- )
	declare "information"
	thread information
		dq info_banner
		dq print_line
		dq new_line

		dq dictionary
		dq load

		.again:
		dq copy
		dq entry_metadata
		predicated immediate_tag, empty_tag
		dq print
		dq print_line
		dq load
		dq copy
		branch_to .again

		dq drop
		dq new_line
		dq return

	; ( entry -- name length immediate?  )
	declare "entry-metadata"
	thread entry_metadata
		dq cell_size
		dq push_add
		dq copy
		dq stash
		dq one
		dq push_add
		dq unstash
		dq load_byte
		dq copy
		dq literal
		dq immediate
		dq push_and
		dq push_is_nzero
		dq swap
		dq literal
		dq immediate
		dq push_not
		dq push_and
		dq swap
		dq return

	; ( -- )
	thread init_dictionary
		dq core_vocabulary
		dq dictionary
		dq store
		dq return

	; ( -- )
	declare "fn{"
	thread define
		dq return

	; ( -- )
	declare "}", immediate
	thread end_define
		dq return

	declare "0"
	constant zero, 0

	declare "true"
	constant true, ~0

	declare "1"
	constant one, 1

	declare "cell-size"
	constant cell_size, 8

	variable line_size, 1
	variable stdin_handle, 1
	variable stdout_handle, 1
	variable line_buffer, (line_buffer_length / 8) + 1 ; +1 to ensure null-termination
	variable current_word_pair, 2

	declare "dictionary"
	variable dictionary, 1

	string status_overfull, `Line overfull\n`
	string newline, `\n`
	string empty_tag, `    `
	string immediate_tag, `*   `
	string info_banner, `Silicon (c) 2023 @daviddetweiler`

section .bss
	data_stack:
		resq stack_depth

	return_stack:
		resq stack_depth

commit_dictionary
