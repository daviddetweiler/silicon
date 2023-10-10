default rel
bits 64

global start

extern ExitProcess
extern GetStdHandle
extern WriteFile
extern ReadFile
extern SetFilePointer
extern CloseHandle

%define tp r15
%define wp r14
%define dp r13
%define rp r12

; While a per-word stack usage may be quite small (perhaps 8 cells at most?) call nesting can be much, much deeper, so
; the data stack must be of a similar size to the return stack. It may be easiest to only ever check for underflow,
; since overflows are unlikely to be recoverable anyways (though I did have a thought about a "circular stack" being
; used to mitigate it without as onerous a runtime cost).
%define stack_depth 1024
%define stack_base(stack) (stack + stack_depth * 8)

%define term_buffer_size 8 * 16
%define formatted_decimal_size 8 * 4
%define arena_size 1024 * 1024
%define source_context_stack_depth 64
%define source_context_cells 4

%define immediate (1 << 7)
%define entry_0 0

%assign dictionary_written 0
%assign dictionary_head 0

%define vt_red `\x1b[31m`
%define vt_default `\x1b[0m`
%define vt_cyan `\x1b[36m`
%define vt_yellow `\x1b[33m`
%define vt_clear `\x1b[2J\x1b[3J\x1b[H`
%define red(string) %strcat(vt_red, string, vt_default)
%define cyan(string) %strcat(vt_cyan, string, vt_default)
%define version_string %strcat(`Silicon (`, git_version, `) (c) 2023 @daviddetweiler`)

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

%macro maybe 1
	dq maybe_execute
	dq %1
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
		jmp next

	; ( -- )
	invoke_thread:
		sub rp, 8
		mov [rp], tp
		lea tp, [wp + 8]

	next:
		mov wp, [tp]
		add tp, 8

	run:
		jmp [wp]

	; ( -- )
	code return
		mov tp, [rp]
		add rp, 8
		jmp next

	; ( -- )
	code exit_process
		xor rcx, rcx
		call ExitProcess

	; ( -- )
	code set_stacks
		lea dp, stack_base(data_stack)
		lea rp, stack_base(return_stack)
		jmp next

	; ( -- leftovers? )
	code test_stacks
		lea rax, stack_base(data_stack)
		cmp dp, rax
		jne .stack_error
		lea rax, stack_base(return_stack)
		cmp rp, rax
		jne .stack_error
		sub dp, 8
		mov qword [dp], 0
		jmp next

		.stack_error:
		sub dp, 8
		mov qword [dp], ~0
		jmp next

	; ( value -- )
	declare "drop"
	code drop
		add dp, 8
		jmp next

	; ( -- value )
	code literal
		mov rax, [tp]
		add tp, 8
		sub dp, 8
		mov [dp], rax
		jmp next

	; ( -- string length )
	invoke_string:
		sub dp, 8 * 2
		mov al, [wp + 8]
		movzx rax, al
		mov [dp], rax
		lea rbx, [wp + 9]
		mov [dp + 8], rbx
		jmp next

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
		jmp next

	; ( -- constant )
	invoke_constant:
		mov rax, [wp + 8]
		sub dp, 8
		mov [dp], rax
		jmp next

	; ( address -- value )
	declare "load"
	code load
		mov rax, [dp]
		mov rax, [rax]
		mov [dp], rax
		jmp next

	; ( value address -- )
	declare "store"
	code store
		mov rax, [dp]
		mov rbx, [dp + 8]
		mov [rax], rbx
		add dp, 8 * 2
		jmp next

	; ( id -- handle )
	code get_handle
		mov rcx, [dp]
		call GetStdHandle
		mov [dp], rax
		jmp next

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
		jmp next

	; ( a b -- (a - b) )
	declare "-"
	code push_subtract
		mov rax, [dp]
		add dp, 8
		sub [dp], rax
		jmp next

	; ( condition -- )
	code branch
		mov rax, [dp]
		add dp, 8
		test rax, rax
		jnz .branch
		add tp, 8
		jmp next

		.branch:
		mov rax, [tp]
		lea tp, [tp + rax + 8]
		jmp next

	; ( a -- (a < 0) )
	declare "0>"
	code push_is_negative
		cmp qword [dp], 0
		jl .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( value -- value value )
	declare "copy"
	code copy
		mov rax, [dp]
		sub dp, 8
		mov [dp], rax
		jmp next

	; ( value -- (value == 0) )
	declare "0="
	code push_is_zero
		mov rax, [dp]
		test rax, rax
		jz .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( value -- (value != 0) )
	declare "0~="
	code push_is_nzero
		mov rax, [dp]
		test rax, rax
		jnz .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( -- )
	code jump
		mov rax, [tp]
		lea tp, [tp + rax + 8]
		jmp next

	; ( a b -- (a + b) )
	declare "+"
	code push_add
		mov rax, [dp]
		add dp, 8
		add [dp], rax
		jmp next

	; ( address -- byte )
	declare "load-byte"
	code load_byte
		mov rax, [dp]
		mov al, [rax]
		movzx rax, al
		mov [dp], rax
		jmp next

	; ( a b -- (a != b) )
	declare "~="
	code push_is_neq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jne .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( a b -- (a == b) )
	declare "="
	code push_is_eq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		je .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( value -- )
	declare "stash"
	code stash
		mov rax, [dp]
		add dp, 8
		sub rp, 8
		mov [rp], rax
		jmp next

	; ( -- value )
	declare "unstash"
	code unstash
		mov rax, [rp]
		add rp, 8
		sub dp, 8
		mov [dp], rax
		jmp next

	; ( a b -- b a )
	declare "swap"
	code swap
		mov rax, [dp]
		xchg rax, [dp + 8]
		mov [dp], rax
		jmp next

	; ( a b -- a b a b )
	declare "copy-pair"
	code copy_pair
		mov rax, [dp]
		mov rbx, [dp + 8]
		sub dp, 8 * 2
		mov [dp], rax
		mov [dp + 8], rbx
		jmp next

	; ( a b -- b )
	declare "nip"
	code nip
		mov rax, [dp]
		add dp, 8
		mov [dp], rax
		jmp next

	; ( a b -- a b a )
	declare "over"
	code over
		mov rax, [dp + 8]
		sub dp, 8
		mov [dp], rax
		jmp next

	; ( value address -- )
	declare "store-byte"
	code store_byte
		mov rax, [dp]
		mov rbx, [dp + 8]
		mov [rax], bl
		add dp, 8 * 2
		jmp next

	; ( a -- ~a )
	declare "~"
	code push_not
		not qword [dp]
		jmp next

	; ( a b -- (a & b) )
	declare "&"
	code push_and
		mov rax, [dp]
		add dp, 8
		and [dp], rax
		jmp next

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
		jmp run

		.true:
		mov wp, rax
		jmp run

	; ( address -- value )
	declare "load-2nd"
	code load_2nd
		mov rax, [dp]
		mov rax, [rax + 8]
		mov [dp], rax
		jmp next

	; ( a b -- )
	declare "drop-pair"
	code drop_pair
		add dp, 8 * 2
		jmp next

	; ( word -- )
	declare "invoke"
	code invoke
		mov wp, [dp]
		add dp, 8
		jmp run

	; ( a b -- (a / b) )
	declare "u/"
	code push_udivide
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		div rbx
		mov [dp], rax
		jmp next

	; ( a b -- (a % b) )
	declare "u%"
	code push_umodulo
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		div rbx
		mov [dp], rdx
		jmp next

	; ( a b -- (a / b) )
	declare "/"
	code push_divide
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		idiv rbx
		mov [dp], rax
		jmp next

	; ( a b -- (a % b) )
	declare "%"
	code push_modulo
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		idiv rbx
		mov [dp], rdx
		jmp next

	; ( n -- -n )
	declare "0-"
	code push_negate
		neg qword [dp]
		jmp next

	; ( a b -- (a >= b) )
	declare ">="
	code push_is_ge
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jge .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( a b -- (a <= b) )
	declare "<="
	code push_is_le
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jle .true
		mov qword [dp], 0
		jmp next

		.true:
		mov qword [dp], ~0
		jmp next

	; ( a b -- (a * b) )
	declare "u*"
	code push_umultiply
		mov rax, [dp]
		add dp, 8
		mul qword [dp]
		mov [dp], rax
		jmp next

	; ( a b -- (a * b) )
	declare "*"
	code push_multiply
		mov rax, [dp]
		add dp, 8
		imul qword [dp]
		mov [dp], rax
		jmp next

	; ( -- )
	declare "break"
	code break
		int3
		jmp next

	; ( a b -- (a | b) )
	declare "|"
	code push_or
		mov rax, [dp]
		add dp, 8
		or [dp], rax
		jmp next

	; ( -- )
	code maybe_execute
		mov rax, [dp]
		add dp, 8
		mov wp, [tp]
		add tp, 8
		test rax, rax
		jz .skip
		jmp run

		.skip:
		jmp next

section .rdata
	; ( -- )
	program:
		dq set_stacks
		dq init_handles
		dq init_source_context
		dq init_current_word
		dq init_dictionary
		dq init_arena

		.accept:
		dq should_exit
		dq load
		branch_to .exit

		dq accept_word
		branch_to .source_ended
		dq current_word
		dq find
		dq copy
		branch_to .found
		dq drop_pair

		dq current_word
		dq parse_number
		branch_to .accept_number
		dq drop

		dq status_unknown
		dq print
		dq current_word
		dq print_line
		dq new_line
		dq term_flush_line
		jump_to .accept

		.found:
		dq swap
		dq push_not
		dq is_assembling
		dq load
		dq push_is_nzero
		dq push_and
		predicated assemble, invoke
		jump_to .accept

		.source_ended:
		dq is_nested_source
		dq push_not
		branch_to .exit
		dq pop_source_context
		jump_to .accept

		.exit:
		dq test_stacks
		maybe report_leftovers
		dq exit_process

		.accept_number:
		dq is_assembling
		dq load
		dq push_not
		branch_to .accept
		dq assemble_literal
		dq assemble
		jump_to .accept

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
	thread term_read_line
		dq term_buffer
		dq literal
		dq term_buffer_size
		dq stdin_handle
		dq load
		dq read_file
		dq drop
		dq zero
		dq over
		dq term_buffer
		dq push_add
		dq store_byte
		dq literal
		dq 2
		dq push_subtract
		dq line_size
		dq store
		dq return

	; ( -- exit? )
	thread accept_line_interactive
		.again:
		dq term_read_line

		dq line_size
		dq load

		dq copy
		dq push_is_negative
		branch_to .eof

		dq push_is_zero
		branch_to .again

		dq term_is_overfull
		branch_to .line_overfull

		dq zero
		dq return

		.line_overfull:
		dq status_overfull
		dq print_line

		.flush:
		dq term_read_line
		dq term_is_overfull
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
	thread term_is_overfull
		dq term_buffer
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
		dq term_buffer
		dq line_size
		dq load
		dq return

	; ( -- exit? )
	thread accept_word
		.again:
		dq current_word
		dq push_add
		dq copy

		dq term_buffer
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

	; ( -- exit? )
	thread accept_line
		dq preloaded_source
		dq load
		predicated accept_line_preloaded, accept_line_interactive
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
		dq term_buffer
		dq zero
		dq current_word_pair
		dq store_pair
		dq return

	; ( ptr -- new-ptr )
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

	; ( ptr -- new-ptr )
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
		dq version

		dq dictionary
		dq load

		.again:
		dq copy
		dq entry_metadata
		predicated immediate_tag, empty_tag
		dq print
		dq seq_yellow
		dq print
		dq print
		dq seq_default
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
		dq copy
		dq entry_immediate
		dq stash
		dq entry_name
		dq unstash
		dq return

	; ( -- )
	thread init_dictionary
		dq core_vocabulary
		dq dictionary
		dq store
		dq return

	; ( -- )
	declare "assemble-literal"
	thread assemble_literal
		dq literal
		dq literal
		dq assemble
		dq return

	; ( -- )
	declare "assemble-thread"
	thread assemble_thread
		dq literal
		dq invoke_thread
		dq assemble
		dq return

	; ( -- )
	declare "assemble-return"
	thread assemble_return
		dq literal
		dq return
		dq assemble
		dq return

	; ( -- )
	declare "assemble-constant"
	thread assemble_constant
		dq literal
		dq invoke_constant
		dq assemble
		dq return

	; ( -- )
	declare "assemble-branch"
	thread assemble_branch
		dq literal
		dq branch
		dq assemble
		dq return

	; ( -- )
	declare "assemble-jump"
	thread assemble_jump
		dq literal
		dq jump
		dq assemble
		dq return

	; ( a-string a-length b-string b-length -- same? )
	declare "string="
	thread string_eq
		dq string_b
		dq store_pair
		dq string_a
		dq store_pair

		dq string_b
		dq load_2nd
		dq string_a
		dq load_2nd
		dq over
		dq push_is_neq
		branch_to .false

		.again:
		dq string_b
		dq load
		dq load_byte
		dq string_a
		dq load
		dq load_byte
		dq push_is_neq
		branch_to .false

		dq one
		dq push_subtract
		dq copy
		dq push_is_zero
		branch_to .true

		dq string_b
		dq load
		dq one
		dq push_add
		dq string_b
		dq store

		dq string_a
		dq load
		dq one
		dq push_add
		dq string_a
		dq store
		jump_to .again

		.false:
		dq drop
		dq zero
		dq return

		.true:
		dq drop
		dq true
		dq return

	; ( string length -- immediate? word? )
	declare "find"
	thread find
		dq dictionary
		dq load

		.again:
		dq stash
		dq copy_pair
		dq unstash
		dq copy
		dq stash
		dq entry_metadata
		dq drop
		dq string_eq
		branch_to .found

		dq unstash
		dq load
		dq copy
		branch_to .again

		dq drop_pair
		dq zero
		dq return

		.found:
		dq drop_pair
		dq unstash
		dq copy
		dq entry_immediate
		dq swap
		dq entry_data_ptr
		dq return

	; ( entry -- data )
	declare "entry-data-ptr"
	thread entry_data_ptr
		dq entry_name
		dq push_add
		dq one
		dq push_add
		dq cell_align
		dq return

	; ( entry -- name length )
	declare "entry-name"
	thread entry_name
		dq cell_size
		dq push_add

		dq copy
		dq one
		dq push_add
		dq swap

		dq load_byte
		dq literal
		dq ~immediate
		dq push_and

		dq return

	; ( entry -- immediate? )
	declare "entry-immediate?"
	thread entry_immediate
		dq cell_size
		dq push_add
		dq load_byte
		dq literal
		dq immediate
		dq push_and
		dq push_is_nzero
		dq return

	; ( address -- aligned-address )
	declare "cell-align"
	thread cell_align
		dq copy
		dq literal
		dq 7
		dq push_and
		dq cell_size
		dq swap
		dq push_subtract
		dq literal
		dq 7
		dq push_and
		dq push_add
		dq return

	; ( -- )
	declare "flush-line"
	thread term_flush_line
		dq current_word
		dq drop
		dq copy
		dq term_buffer
		dq push_subtract
		dq line_size
		dq load
		dq swap
		dq push_subtract
		dq current_word_pair
		dq store_pair
		dq return

	; ( -- )
	declare "version"
	thread version
		dq version_banner
		dq print_line
		dq new_line
		dq return

	; ( n -- )
	declare "print-u#"
	thread print_unumber
		dq formatted_decimal
		dq literal
		dq formatted_decimal_size
		dq push_add
		dq copy
		dq stash
		dq stash

		.again:
		dq copy
		dq ten
		dq push_umodulo
		dq literal
		dq '0'
		dq push_add
		dq unstash
		dq one
		dq push_subtract
		dq swap
		dq over
		dq store_byte
		dq stash
		dq ten
		dq push_udivide
		dq copy
		branch_to .again

		dq drop
		dq unstash
		dq unstash
		dq over
		dq push_subtract
		dq print
		dq return

	; ( n -- )
	declare "print-#"
	thread print_number
		dq copy
		dq push_is_negative
		branch_to .negative
		dq print_unumber
		dq return

		.negative:
		dq negative
		dq print
		dq push_negate
		dq print_unumber
		dq return

	; ( -- )
	thread report_leftovers
		dq status_leftovers
		dq print_line
		dq term_read_line
		dq return

	; ( char -- digit? )
	thread is_digit
		dq copy
		dq literal
		dq '0'
		dq push_is_ge
		dq stash
		dq literal
		dq `9`
		dq push_is_le
		dq unstash
		dq push_and
		dq return

	; ( string length -- n number? )
	declare "parse-u#"
	thread parse_unumber
		dq parsed_number
		dq store_pair
		dq zero
		dq stash

		.again:
		dq parsed_number
		dq load
		dq load_byte
		dq copy
		dq is_digit
		dq push_not
		branch_to .nan
		dq literal
		dq '0'
		dq push_subtract
		dq unstash
		dq ten
		dq push_umultiply
		dq push_add
		dq stash

		dq parsed_number
		dq load
		dq one
		dq push_add
		dq parsed_number
		dq load_2nd
		dq one
		dq push_subtract
		dq copy
		dq stash
		dq parsed_number
		dq store_pair
		dq unstash
		branch_to .again

		dq unstash
		dq true
		dq return

		.nan:
		dq unstash
		dq drop
		dq zero
		dq return

	; ( string length -- n number? )
	declare "parse-#"
	thread parse_number
		dq over
		dq load_byte
		dq literal
		dq `-`
		dq push_is_eq
		branch_to .negative
		dq parse_unumber
		dq return

		.negative:
		dq copy
		dq one
		dq push_is_eq
		branch_to .nan
		dq one
		dq push_subtract
		dq swap
		dq one
		dq push_add
		dq swap
		dq parse_unumber
		dq swap
		dq push_negate
		dq swap
		dq return

		.nan:
		dq drop_pair
		dq zero
		dq zero
		dq return

	declare "exit"
	thread exit
		dq true
		dq should_exit
		dq store
		dq return

	; ( -- word? )
	declare "create"
	thread create
		dq accept_word
		branch_to .rejected
		dq current_word
		dq copy
		dq literal
		dq 128
		dq push_is_ge
		branch_to .too_long
		dq arena_top
		dq load
		dq stash
		dq cell_align_arena
		dq dictionary
		dq load
		dq assemble
		dq copy
		dq assemble_byte
		dq assemble_string
		dq zero
		dq assemble_byte
		dq cell_align_arena
		dq unstash
		dq return

		.too_long:
		dq drop_pair
		dq unstash
		dq drop
		dq status_word_too_long
		dq print_line

		.rejected:
		dq zero
		dq return

	; ( -- )
	thread cell_align_arena
		dq arena_top
		dq load
		dq cell_align
		dq arena_top
		dq store
		dq return

	; ( cell -- )
	declare "assemble"
	thread assemble
		dq arena_top
		dq load
		dq store
		dq arena_top
		dq load
		dq cell_size
		dq push_add
		dq arena_top
		dq store
		dq return

	; ( byte -- )
	declare "assemble-byte"
	thread assemble_byte
		dq arena_top
		dq load
		dq store_byte
		dq arena_top
		dq load
		dq one
		dq push_add
		dq arena_top
		dq store
		dq return

	; ( string length -- )
	declare "assemble-string"
	thread assemble_string
		dq string_a
		dq store_pair

		.again:
		dq string_a
		dq load
		dq load_byte
		dq assemble_byte

		dq string_a
		dq load
		dq one
		dq push_add

		dq string_a
		dq load_2nd
		dq one
		dq push_subtract

		dq copy
		dq stash

		dq string_a
		dq store_pair

		dq unstash
		branch_to .again

		dq return

	; ( -- )
	thread init_arena
		dq arena_base
		dq arena_top
		dq store
		dq return

	; ( -- )
	declare "clear"
	thread clear
		dq seq_clear
		dq print
		dq return

	; ( -- )
	declare "immediate"
	thread make_immediate
		dq dictionary
		dq load
		dq cell_size
		dq push_add
		dq copy
		dq load_byte
		dq literal
		dq immediate
		dq push_or
		dq swap
		dq store_byte
		dq return

	; ( -- ptr )
	declare "assembly-ptr"
	thread assembly_ptr
		dq arena_top
		dq load
		dq return

	; ( -- word? )
	declare "get-word"
	thread get_word
		dq accept_word
		branch_to .cancelled
		dq current_word
		dq find
		dq nip
		dq return

		.cancelled:
		dq zero
		dq return

	; I believe that it's possible to implement file interpretation just by replacing `accept-line`
	; Maybe rename accept_line_interactive to accept_line_interactive, etc.

	; ( -- exit? )
	thread accept_line_preloaded
		dq true
		dq return

	; The context stack should be bounds-checked; `include` should report if recursion depth has been exceeded

	; ( -- ptr-line-size )
	thread line_size
		dq source_context
		dq load
		dq return

	; ( -- ptr-preloaded-source )
	thread preloaded_source
		dq source_context
		dq load
		dq cell_size
		dq push_add
		dq return

	; ( -- ptr-word-pair )
	thread current_word_pair
		dq source_context
		dq load
		dq cell_size
		dq copy
		dq push_add
		dq push_add
		dq return

	; ( -- )
	thread init_source_context
		dq source_context_stack
		dq source_context
		dq store
		dq return

	; ( -- )
	thread push_source_context
		dq return

	; ( -- )
	thread pop_source_context
		dq return

	; ( -- nested? )
	thread is_nested_source
		dq source_context
		dq load
		dq source_context_stack
		dq push_is_neq
		dq return

	declare "0"
	constant zero, 0

	declare "true"
	constant true, ~0

	declare "1"
	constant one, 1

	declare "cell-size"
	constant cell_size, 8

	declare "10"
	constant ten, 10

	; Begin interpreter state variables

	declare "is-assembling"
	variable is_assembling, 1

	declare "partial-definition"
	variable partial_definition, 1

	declare "dictionary"
	variable dictionary, 1

	variable arena_top, 1
	variable should_exit, 1
	variable source_context, 1

	; End interpreter state variables

	variable stdin_handle, 1
	variable stdout_handle, 1
	variable term_buffer, (term_buffer_size / 8) + 1 ; +1 to ensure null-termination
	variable string_a, 2
	variable string_b, 2
	variable formatted_decimal, formatted_decimal_size / 8
	variable parsed_number, 2
	variable arena_base, arena_size / 8
	variable source_context_stack, source_context_stack_depth * source_context_cells

	string status_overfull, red(`Line overfull\n`)
	string status_unknown, red(`Unknown word: `)
	string status_leftovers, red(`Leftovers on stack; press enter...`)
	string status_word_too_long, red(`Word is too long for dictionary entry\n`)
	string newline, `\n`
	string empty_tag, `    `
	string immediate_tag, red(`*   `)
	string version_banner, cyan(version_string)
	string negative, `-`
	string seq_clear, vt_clear
	string seq_yellow, vt_yellow
	string seq_default, vt_default

section .bss
	data_stack:
		resq stack_depth

	return_stack:
		resq stack_depth

commit_dictionary
