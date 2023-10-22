default rel
bits 64

global start

%define tp r15
%define wp r14
%define dp r13
%define rp r12

; While a per-word stack usage may be quite small (perhaps 8 cells at most?) the call stack can be much, much deeper, so
; the data stack must be of a similar size to the return stack. It may be easiest to only ever check for underflow,
; since overflows are unlikely to be recoverable anyways (though I did have a thought about a "circular stack" being
; used to mitigate it without as onerous a runtime cost).
%define stack_depth 1024
%define stack_base(stack) (stack + stack_depth * 8)

%define term_buffer_size 8 * 16
%define arena_size 1024 * 1024
%define source_context_stack_depth 64
%define source_context_cells 5

%define immediate (1 << 7)

%ifndef standalone
	%define entry_0 -image_base
%else
	%define entry_0 0
%endif

%assign dictionary_written 0
%assign dictionary_head 0

%define vt_red `\x1b[31m`
%define vt_default `\x1b[0m`
%define vt_cyan `\x1b[36m`
%define vt_yellow `\x1b[33m`
%define vt_clear `\x1b[2J\x1b[H`
%define vt_clear_scrollback `\x1b[3J`
%define red(string) %strcat(vt_red, string, vt_default)
%define cyan(string) %strcat(vt_cyan, string, vt_default)
%define yellow(string) %strcat(vt_yellow, string, vt_default)
%define version_string %strcat(`Silicon `, git_version)

%define image_base 0x2000000000

%ifndef standalone
	%define address(x) (x) + image_base
%else
	%define address(x) x
%endif

%macro da 1
	dq address(%1)
%endmacro

%macro code_field 2
	align 8
	%1:
		da %2
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
		db %strlen(%2), %2, 0
%endmacro

%macro constant 2
	code_field %1, invoke_constant
		dq %2
%endmacro

%macro variable 2
	constant %1, address(%%storage)
	[section .bss]
		%%storage:
			resq %2

	__?SECT?__
%endmacro

%macro branch_to 1
	da branch
	dq %1 - %%here

	%%here:
%endmacro

%macro jump_to 1
	da jump
	dq %1 - %%here

	%%here:
%endmacro

%macro predicated 2
	da predicate
	da %1
	da %2
%endmacro

%macro maybe 1
	da maybe_execute
	da %1
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
			da dictionary_entry(dictionary_head)
			db %strlen(%1) | %2, %1, 0

	__?SECT?__

	%assign dictionary_head n

	%pop
%endmacro

%macro commit_dictionary 0
	section .rdata
		declare "kernel-dict"
		constant core_vocabulary, address(dictionary_entry(dictionary_head))
		%assign dictionary_written 1
%endmacro

%macro run 0
	jmp [wp]
%endmacro

%macro next 0
	mov wp, [tp]
	add tp, 8
	run
%endmacro

%ifndef standalone
	%define id_ExitProcess 0
	%define id_GetStdHandle 1
	%define id_WriteFile 2
	%define id_ReadFile 3
	%define id_CreateFileA 4
	%define id_SetFilePointer 5
	%define id_CloseHandle 6
	%define id_VirtualAlloc 7
	%define id_VirtualFree 8
	%define n_imports 9

	%define id(name) id_ %+ name
	%macro get_import 1
		mov rcx, rbp
		lea rdx, name_ %+ %1
		call rdi
		mov [table_imports + 8 * id(%1)], rax
	%endmacro

	%macro name 1
		name_ %+ %1:
			db %str(%1), 0
	%endmacro
%else
	extern ExitProcess
	extern GetStdHandle
	extern WriteFile
	extern ReadFile
	extern CreateFileA
	extern SetFilePointer
	extern CloseHandle
	extern VirtualAlloc
	extern VirtualFree
%endif

%macro call_import 1
	%ifndef standalone
		call [table_imports + 8 * id(%1)]
	%else
		call %1
	%endif
%endmacro

section .text
	begin_text:

section .rdata
	begin_rdata:

section .bss
	begin_bss:

section .text
	%ifndef standalone
		dq end_bss - begin_bss
	%endif

	; ( -- )
	start:
		%ifdef standalone
			sub rsp, 8 + 8 * 16 ; enough room for 16 parameters, plus stack alignment
		%else
			mov [get_module_handle], rcx
			mov [get_proc_address], rdx
		%endif
		lea tp, program
		next

	; ( -- )
	invoke_thread:
		sub rp, 8
		mov [rp], tp
		lea tp, [wp + 8]
		next

	; ( -- )
	declare "return"
	code return
		mov tp, [rp]
		add rp, 8
		next

	; ( code -- )
	code exit_process
		mov rcx, [dp]
		call_import ExitProcess

	; ( -- )
	code set_data_stack
		lea dp, stack_base(data_stack)
		next

	; ( -- )
	code set_return_stack
		lea rp, stack_base(return_stack)
		next

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
		next

		.stack_error:
		sub dp, 8
		mov qword [dp], ~0
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

	; ( -- string length )
	invoke_string:
		sub dp, 8 * 2
		movzx rax, byte [wp + 8]
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
		call_import WriteFile
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
		call_import GetStdHandle
		mov [dp], rax
		next

	; ( buffer length handle -- count succeeded? )
	declare "read-file"
	code read_file
		mov rcx, [dp]
		mov rdx, [dp + 8 * 2]
		mov r8, [dp + 8]
		lea r9, [dp + 8 * 2]
		xor rax, rax
		mov [r9], rax
		mov qword [rsp + 8 * 4], rax
		call_import ReadFile
		add dp, 8
		test rax, rax
		jz .failed
		mov qword [dp], -1
		next

		.failed:
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
		jl .all_ones
		mov qword [dp], 0
		next

		.all_ones:
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
		jz .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( value -- (value != 0) )
	declare "0~="
	code push_is_nzero
		mov rax, [dp]
		test rax, rax
		jnz .all_ones
		mov qword [dp], 0
		next

		.all_ones:
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
		movzx rax, byte [rax]
		mov [dp], rax
		next

	; ( a b -- (a != b) )
	declare "~="
	code push_is_neq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jne .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( a b -- (a == b) )
	declare "="
	code push_is_eq
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		je .all_ones
		mov qword [dp], 0
		next

		.all_ones:
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
		jnz .all_ones
		mov wp, rbx
		run

		.all_ones:
		mov wp, rax
		run

	; ( condition -- )
	code predicate_unary
		mov rax, [tp]
		add tp, 8
		mov rcx, [dp]
		add dp, 8
		test rcx, rcx
		jz .skip
		mov wp, rax
		run

		.skip:
		next

	; ( address -- value )
	declare "load-2nd"
	code load_2nd
		mov rax, [dp]
		mov rax, [rax + 8]
		mov [dp], rax
		next

	; ( value address -- )
	declare "store-2nd"
	code store_2nd
		mov rax, [dp]
		mov rbx, [dp + 8]
		mov [rax + 8], rbx
		add dp, 8 * 2
		next

	; ( a b -- )
	declare "drop-pair"
	code drop_pair
		add dp, 8 * 2
		next

	; ( word -- )
	declare "invoke"
	code invoke
		mov wp, [dp]
		add dp, 8
		run

	; ( a b -- (a / b) )
	declare "u/"
	code push_udivide
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		div rbx
		mov [dp], rax
		next

	; ( a b -- (a % b) )
	declare "u%"
	code push_umodulo
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		div rbx
		mov [dp], rdx
		next

	; ( a b -- (a / b) )
	declare "/"
	code push_divide
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		idiv rbx
		mov [dp], rax
		next

	; ( a b -- (a % b) )
	declare "%"
	code push_modulo
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		idiv rbx
		mov [dp], rdx
		next

	; ( n -- -n )
	declare "0-"
	code push_negate
		neg qword [dp]
		next

	; ( a b -- (a >= b) )
	declare ">="
	code push_is_ge
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jge .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( a b -- (a <= b) )
	declare "<="
	code push_is_le
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jle .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( a b -- (a > b) )
	declare ">"
	code push_is_gt
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jg .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( a b -- (a < b) )
	declare "<"
	code push_is_lt
		mov rax, [dp]
		add dp, 8
		cmp [dp], rax
		jl .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( a b -- (a * b) )
	declare "u*"
	code push_umultiply
		mov rax, [dp]
		add dp, 8
		mul qword [dp]
		mov [dp], rax
		next

	; ( a b -- (a * b) )
	declare "*"
	code push_multiply
		mov rax, [dp]
		add dp, 8
		imul qword [dp]
		mov [dp], rax
		next

	; ( -- )
	declare "break"
	code break
		int3
		next

	; ( a b -- (a | b) )
	declare "|"
	code push_or
		mov rax, [dp]
		add dp, 8
		or [dp], rax
		next

	; ( -- )
	code maybe_execute
		mov rax, [dp]
		add dp, 8
		mov wp, [tp]
		add tp, 8
		test rax, rax
		jz .skip
		run

		.skip:
		next

	; ( handle offset mode -- old-ptr? )
	;
	; We treat -1 as an error sentinel
	declare "set-file-ptr"
	code set_file_ptr
		mov rcx, [dp + 8 * 2]
		mov rdx, [dp + 8]
		lea r8, [dp + 8 + 4]
		mov r9, [dp]
		call_import SetFilePointer

		mov rcx, 4294967295 ; INVALID_SET_FILE_POINTER
		cmp rax, rcx
		jne .success
		call_import SetFilePointer
		test rax, rax
		jnz .success

		add dp, 8 * 2
		mov qword [dp], -1
		next

		.success:
		mov [dp + 8], eax
		mov rax, [dp + 8]
		add dp, 8 * 2
		mov [dp], rax
		next

	; ( handle -- )
	declare "close-handle"
	code close_handle
		mov rcx, [dp]
		call_import CloseHandle
		add dp, 8
		next

	; ( c-string -- handle )
	declare "open-file"
	code open_file
		mov rcx, [dp]
		mov rdx, 0x80000000
		xor r8, r8
		xor r9, r9
		mov qword [rsp + 8 * 4], 3
		mov qword [rsp + 8 * 5], 0x80
		mov qword [rsp + 8 * 6], r9
		call_import CreateFileA
		cmp rax, -1
		jne .success
		mov rax, 0

		.success:
		mov [dp], rax
		next

	; ( size -- address )
	declare "allocate-pages"
	code allocate_pages
		xor rcx, rcx
		mov rdx, [dp]
		mov r8, 0x1000 ; MEM_COMMIT
		mov r9, 0x04 ; PAGE_READWRITE
		call_import VirtualAlloc
		mov [dp], rax
		next

	; ( address -- succeeded? )
	declare "free-pages"
	code free_pages
		mov rcx, [dp]
		xor rdx, rdx
		mov r8, 0x8000 ; MEM_RELEASE
		call_import VirtualFree
		mov [dp], rax
		next

	; ( -- address )
	invoke_variable:
		lea rax, [wp + 8]
		sub dp, 8
		mov [dp], rax
		next

	; ( -- )
	declare "crash"
	code crash
		mov rcx, 7
		int 0x29 ; Good ol' __fastfail(FAST_FAIL_FATAL_APP_EXIT)
		next

	; ( a-string a-length b-string b-length -- same? )
	declare "string="
	code string_eq
		mov rcx, [dp + 8 * 2]
		cmp rcx, [dp]
		jne .not_equal
		mov rsi, [dp + 8 * 3]
		mov rdi, [dp + 8]
		repe cmpsb
		test rcx, rcx
		jnz .not_equal
		mov al, [rsi - 1]
		cmp al, [rdi - 1]
		jne .not_equal
		add dp, 8 * 3
		mov qword [dp], -1
		next

		.not_equal:
		add dp, 8 * 3
		xor rax, rax
		mov [dp], rax
		next

	; ( byte-ptr length destination -- )
	declare "copy-blob"
	code copy_blob
		mov rcx, [dp + 8]
		mov rsi, [dp + 8 * 2]
		mov rdi, [dp]
		rep movsb
		add dp, 8 * 3
		next

	; ( entry -- name length )
	declare "entry-name"
	code entry_name
		mov rax, [dp]
		add rax, 9
		movzx rbx, byte [rax - 1]
		and rbx, ~immediate
		mov [dp], rax
		sub dp, 8
		mov [dp], rbx
		next

	; ( -- value )
	declare "peek-stash"
	code peek_stash
		mov rax, [rp]
		sub dp, 8
		mov [dp], rax
		next

	; ( a b c -- a b c a b )
	declare "pair-over"
	code pair_over
		mov rax, [dp + 8 * 2]
		mov rbx, [dp + 8]
		sub dp, 8 * 2
		mov [dp + 8], rax
		mov [dp], rbx
		next

	; ( a b c -- a b c a )
	declare "over-pair"
	code over_pair
		mov rax, [dp + 8 * 2]
		sub dp, 8
		mov [dp], rax
		next

	; ( a b c -- b c a )
	declare "rot-down"
	code rot_down
		mov rax, [dp + 8 * 2]
		mov rbx, [dp + 8]
		mov rcx, [dp]
		mov [dp + 8 * 2], rbx
		mov [dp + 8], rcx
		mov [dp], rax
		next

	%ifndef standalone
		code set_imports
			mov rsi, [get_module_handle]
			mov rdi, [get_proc_address]

			lea rcx, kernel32
			call rsi
			mov rbp, rax
			get_import ExitProcess
			get_import GetStdHandle
			get_import WriteFile
			get_import ReadFile
			get_import CreateFileA
			get_import SetFilePointer
			get_import CloseHandle
			get_import VirtualAlloc
			get_import VirtualFree
			next
	%endif
			
section .rdata
	align 8
	; ( -- )
	program:
		%ifndef standalone
			da set_imports
		%endif
		da set_return_stack
		da set_data_stack
		da init_handles
		da init_assembler
		da init_source_context
		da init_current_word
		da init_dictionary
		da init_arena
		da init_term_buffer
		da load_init_library

	interpret:
		da should_exit
		da load
		branch_to .exit

		da accept_word
		branch_to .source_ended
		da get_current_word
		da find
		da copy
		branch_to .found
		da drop_pair

		da get_current_word
		da parse_number
		branch_to .accept_number
		da drop

		da status_unknown
		da print
		da get_current_word
		da print_line
		da new_line
		da soft_fault

		.found:
		da swap
		da push_not
		da is_assembling
		da load
		da push_is_nzero
		da push_and
		predicated assemble, invoke
		jump_to interpret

		.source_ended:
		da is_nested_source
		da push_not
		branch_to .exit
		da pop_source_context
		da zero
		da am_initing
		da store
		jump_to interpret

		.exit:
		da test_stacks
		maybe report_leftovers
		da zero
		da exit_process

		.accept_number:
		da is_assembling
		da load
		da push_not
		branch_to interpret
		da assemble_literal
		da assemble
		jump_to interpret

	; ( -- )
	thread init_term_buffer
		da zero
		da term_buffer
		da store_byte
		da return

	; ( -- )
	declare "soft-fault"
	thread soft_fault
		da is_nested_source
		maybe hard_fault
		da flush_line

		da is_assembling
		da load
		da push_not
		branch_to .exit
		da current_definition
		da load
		da arena_top
		da store

		.exit:
		da init_assembler
		da set_return_stack
		jump_to interpret

	; ( -- )
	thread init_assembler
		da zero
		da copy
		da is_assembling
		da store
		da current_definition
		da store
		da return

	; ( -- )
	;
	; This makes some rather dubious assumptions about the interpreter state; amounting to assuming that hard faults
	; have left the interpreter in partial, unspecified, but otherwise valid state that it must simply reset from
	declare "hard-fault"
	thread hard_fault
		da am_initing
		da load
		branch_to .die
		da status_abort
		da print_line
		jump_to program

		.die:
		da status_bad_init
		da print_line
		da term_read_line
		da all_ones
		da exit_process

	; ( -- )
	thread load_init_library
		da literal
		da core_lib
		da set_up_source_text
		da all_ones
		da am_initing
		da store
		da return

	; ( handle -- )
	thread set_up_preloaded_source
		da copy
		da load_source_file
		da swap
		da close_handle
		da set_up_source_text
		da return

	; ( buffer -- )
	thread set_up_source_text
		da push_source_context

		da copy
		da preloaded_source
		da store

		da copy
		da zero
		da current_word
		da store_pair

		da copy
		da line_start
		da store

		da set_line_size
		da return

	; ( handle -- source? )
	thread load_source_file
		da copy
		da stash
		da file_size
		da copy
		da all_ones
		da push_is_neq
		branch_to .allocate
		da drop
		da unstash
		da drop
		jump_to .failed

		.allocate:
		da copy
		da one
		da push_add
		da allocate_pages
		da copy
		da push_is_nzero
		branch_to .read
		da drop_pair
		da unstash
		da drop
		jump_to .failed

		.read:
		da copy
		da unstash
		da swap
		da stash
		da stash
		da swap
		da unstash
		da read_file
		da nip
		branch_to .succeeded
		da unstash
		da free_pages
		da drop
		jump_to .failed

		.succeeded:
		da unstash
		da return

		.failed:
		da status_source_not_loaded
		da print_line
		da soft_fault

	; ( handle -- size? )
	;
	; We treat -1 as an error sentinel
	declare "file-size"
	thread file_size
		da copy
		da zero
		da literal
		dq 2
		da set_file_ptr
		da copy
		da all_ones
		da push_is_eq
		branch_to .exit

		da swap
		da zero
		da zero
		da set_file_ptr
		da swap
		da over
		da all_ones
		da push_is_neq
		branch_to .exit
		da swap

		.exit:
		da nip
		da return

	; ( string length -- )
	declare "print"
	thread print
		da stdout_handle
		da load
		da write_file
		da drop
		da return

	; ( -- )
	thread init_handles
		da literal
		dq -10
		da get_handle
		da stdin_handle
		da store

		da literal
		dq -11
		da get_handle
		da stdout_handle
		da store

		da return

	; ( -- )
	declare "nl"
	thread new_line
		da newline
		da print
		da return

	; ( -- count )
	thread term_read_line
		da term_buffer
		da literal
		dq term_buffer_size
		da stdin_handle
		da load
		da read_file
		da drop
		da zero
		da over
		da term_buffer
		da push_add
		da store_byte
		da literal
		dq 2
		da push_subtract
		da line_size
		da store
		da return

	; ( -- exit? )
	thread accept_line_interactive
		da init_current_word
		da term_buffer
		da line_start
		da store

		.again:
		da term_read_line

		da line_size
		da load

		da copy
		da push_is_negative
		branch_to .eof

		da push_is_zero
		branch_to .again

		da term_is_overfull
		branch_to .line_overfull

		da zero
		da return

		.line_overfull:
		da status_overfull
		da print_line

		.flush:
		da term_read_line
		da term_is_overfull
		branch_to .flush
		jump_to .again

		.eof:
		da drop
		da all_ones
		da return

	; ( string length -- )
	declare "print-line"
	thread print_line
		da print
		da new_line
		da return

	; ( -- overfull? )
	thread term_is_overfull
		da term_buffer
		da line_size
		da load
		da one
		da push_add
		da push_add
		da load_byte
		da literal
		dq `\n`
		da push_is_neq
		da return

	; ( -- line length )
	thread current_line
		da term_buffer
		da line_size
		da load
		da return

	; ( -- exit? )
	thread accept_word
		.again:
		da get_current_word
		da push_add
		da copy

		da line_start
		da load
		da push_subtract
		da line_size
		da load
		da push_is_eq
		branch_to .refill

		da consume_space
		da copy
		da load_byte
		da push_is_zero
		branch_to .refill
		da copy
		da consume_word
		da copy_pair
		da swap
		da push_subtract
		da nip

		da current_word
		da store_pair
		da zero
		da return

		.refill:
		da drop
		da accept_line
		branch_to .exit
		jump_to .again

		.exit:
		da all_ones
		da return

	; ( -- exit? )
	declare "accept-line"
	thread accept_line
		da preloaded_source
		da load
		predicated accept_line_preloaded, accept_line_interactive
		da return

	; ( a b address -- )
	declare "store-pair"
	thread store_pair
		da copy
		da stash
		da cell_size
		da push_add
		da store
		da unstash
		da store
		da return

	; ( address -- a b )
	declare "load-pair"
	thread load_pair
		da copy
		da cell_size
		da push_add
		da stash
		da load
		da unstash
		da load
		da return

	; ( -- word length )
	thread get_current_word
		da current_word
		da load_pair
		da return

	; ( -- )
	thread init_current_word
		da term_buffer
		da zero
		da current_word
		da store_pair
		da return

	; ( ptr -- new-ptr )
	thread consume_space
		.again:
		da copy
		da load_byte
		da is_space
		branch_to .advance
		da return

		.advance:
		da one
		da push_add
		jump_to .again

	; ( ptr -- new-ptr )
	thread consume_word
		.again:
		da copy
		da load_byte
		da copy
		da push_is_zero
		branch_to .return
		da copy
		da is_space
		branch_to .return
		da drop
		da one
		da push_add
		jump_to .again

		.return:
		da drop
		da return

	; ( char -- space? )
	;
	; Here's the issue: accept_word functionally implements the regex `[ \n\r\t]*([^ \n\r\t]+)?`
	; Because of that, a whitespace-only line will just run away into eternity. As such, it needs to
	; be contractual that accept_line will strip out empty lines.
	thread is_space
		da copy
		da literal
		dq ` `
		da push_is_eq
		branch_to .all_ones

		da copy
		da literal
		dq `\t`
		da push_is_eq
		branch_to .all_ones

		da copy
		da literal
		dq `\r`
		da push_is_eq
		branch_to .all_ones

		da copy
		da literal
		dq `\n`
		da push_is_eq
		branch_to .all_ones

		da drop
		da zero
		da return

		.all_ones:
		da drop
		da all_ones
		da return

	; ( -- )
	thread init_dictionary
		da core_vocabulary
		da dictionary
		da store
		da return

	; ( -- )
	declare "assemble-literal"
	thread assemble_literal
		da literal
		da literal
		da assemble
		da return

	; ( -- )
	declare "assemble-invoke-thread"
	thread assemble_invoke_thread
		da literal
		da invoke_thread
		da assemble
		da return

	; ( -- )
	declare "assemble-return"
	thread assemble_return
		da literal
		da return
		da assemble
		da return

	; ( -- )
	declare "assemble-invoke-constant"
	thread assemble_invoke_constant
		da literal
		da invoke_constant
		da assemble
		da return

	; ( -- )
	declare "assemble-branch"
	thread assemble_branch
		da literal
		da branch
		da assemble
		da return

	; ( -- )
	declare "assemble-jump"
	thread assemble_jump
		da literal
		da jump
		da assemble
		da return

	; ( -- )
	declare "assemble-invoke-string"
	thread assemble_invoke_string
		da literal
		da invoke_string
		da assemble
		da return

	; ( -- )
	declare "assemble-invoke-variable"
	thread assemble_invoke_variable
		da literal
		da invoke_variable
		da assemble
		da return

	; ( string length -- immediate? word? )
	declare "find"
	thread find
		da dictionary
		da load

		.again:
		da pair_over
		da over_pair
		da entry_name
		da string_eq
		branch_to .found
		da load
		da copy
		branch_to .again

		da drop_pair
		da zero
		da return

		.found:
		da stash
		da drop_pair
		da unstash
		da copy
		da entry_immediate
		da swap
		da entry_data_ptr
		da return

	; ( entry -- data )
	declare "entry-data-ptr"
	thread entry_data_ptr
		da entry_name
		da push_add
		da one
		da push_add
		da cell_align
		da return

	; ( entry -- immediate? )
	declare "entry-immediate?"
	thread entry_immediate
		da cell_size
		da push_add
		da load_byte
		da literal
		dq immediate
		da push_and
		da push_is_nzero
		da return

	; ( address -- aligned-address )
	declare "cell-align"
	thread cell_align
		da copy
		da literal
		dq 7
		da push_and
		da cell_size
		da swap
		da push_subtract
		da literal
		dq 7
		da push_and
		da push_add
		da return

	; ( -- )
	declare "flush-line"
	thread flush_line
		da get_current_word
		da drop
		da copy
		da line_start
		da load
		da push_subtract
		da line_size
		da load
		da swap
		da push_subtract
		da current_word
		da store_pair
		da return

	; ( -- )
	thread report_leftovers
		da status_stacks_unset
		da print_line
		da term_read_line
		da return

	; ( char -- digit? )
	thread is_digit
		da copy
		da literal
		dq '0'
		da push_is_ge
		da stash
		da literal
		dq `9`
		da push_is_le
		da unstash
		da push_and
		da return

	; ( string length -- n number? )
	declare "parse-u#"
	thread parse_unumber
		da parsed_number
		da store_pair
		da zero
		da stash

		.again:
		da parsed_number
		da load
		da load_byte
		da copy
		da is_digit
		da push_not
		branch_to .nan
		da literal
		dq '0'
		da push_subtract
		da unstash
		da ten
		da push_umultiply
		da push_add
		da stash

		da parsed_number
		da load
		da one
		da push_add
		da parsed_number
		da load_2nd
		da one
		da push_subtract
		da copy
		da stash
		da parsed_number
		da store_pair
		da unstash
		branch_to .again

		da unstash
		da all_ones
		da return

		.nan:
		da unstash
		da drop
		da zero
		da return

	; ( string length -- n number? )
	declare "parse-#"
	thread parse_number
		da over
		da load_byte
		da literal
		dq `-`
		da push_is_eq
		branch_to .negative
		da parse_unumber
		da return

		.negative:
		da copy
		da one
		da push_is_eq
		branch_to .nan
		da one
		da push_subtract
		da swap
		da one
		da push_add
		da swap
		da parse_unumber
		da swap
		da push_negate
		da swap
		da return

		.nan:
		da drop_pair
		da zero
		da zero
		da return

	declare "exit"
	thread exit
		da all_ones
		da should_exit
		da store
		da return

	; ( -- word? )
	declare "create:"
	thread create
		da current_definition
		da load
		da push_is_zero
		branch_to .ok
		da status_nested_def
		da print_line
		da soft_fault

		.ok:
		da accept_word
		branch_to .rejected
		da get_current_word
		da copy
		da literal
		dq 128
		da push_is_ge
		branch_to .too_long
		da cell_align_arena
		da arena_top
		da load
		da stash
		da dictionary
		da load
		da assemble
		da copy
		da assemble_byte
		da assemble_blob
		da zero
		da assemble_byte
		da cell_align_arena
		da unstash
		da return

		.too_long:
		da drop_pair
		da unstash
		da drop
		da status_word_too_long
		da print_line
		da soft_fault

		.rejected:
		da status_no_word
		da print_line
		da soft_fault

	; ( -- )
	declare "cell-align-arena"
	thread cell_align_arena
		da arena_top
		da load
		da cell_align
		da arena_top
		da store
		da return

	; ( cell -- )
	declare "assemble"
	thread assemble
		da arena_top
		da load
		da store
		da arena_top
		da load
		da cell_size
		da push_add
		da arena_top
		da store
		da return

	; ( byte -- )
	declare "assemble-byte"
	thread assemble_byte
		da arena_top
		da load
		da store_byte
		da arena_top
		da load
		da one
		da push_add
		da arena_top
		da store
		da return

	; ( byte-ptr length -- )
	declare "assemble-blob"
	thread assemble_blob
		da copy
		da stash
		da assembly_ptr
		da copy_blob
		da assembly_ptr
		da unstash
		da push_add
		da arena_top
		da store
		da return

	; ( -- )
	thread init_arena
		da arena_base
		da arena_top
		da store
		da return

	; ( -- )
	declare "immediate"
	thread make_immediate
		da dictionary
		da load
		da cell_size
		da push_add
		da copy
		da load_byte
		da literal
		dq immediate
		da push_or
		da swap
		da store_byte
		da return

	; ( -- ptr )
	declare "assembly-ptr"
	thread assembly_ptr
		da arena_top
		da load
		da return

	; ( -- word? )
	declare "get-word:"
	thread get_word
		da accept_word
		branch_to .cancelled
		da get_current_word
		da find
		da nip
		da return

		.cancelled:
		da zero
		da return

	; ( -- exit? )
	thread accept_line_preloaded
		da get_current_word
		da push_add

		da copy
		da load_byte
		branch_to .next_line
		da drop
		da all_ones
		da return

		.again:
		da one
		da push_add

		.next_line:
		da copy
		da load_byte
		da is_space
		branch_to .again

		da copy
		da zero
		da current_word
		da store_pair

		da copy
		da line_start
		da store
		da set_line_size
		da zero
		da return

	; ( line-ptr -- )
	thread set_line_size
		da copy

		.again:
		da copy
		da load_byte
		da literal ; Assumes CRLF line endings :(
		dq `\r`
		da push_is_eq
		branch_to .found_line_end
		da copy
		da load_byte
		da push_is_zero
		branch_to .found_line_end
		da one
		da push_add
		jump_to .again

		.found_line_end:
		da swap
		da push_subtract
		da line_size
		da store
		da return

	; The context stack should be bounds-checked; `include` should report if recursion depth has been exceeded

	; ( -- ptr-line-size )
	declare "line-size"
	thread line_size
		da source_context
		da load
		da return

	; ( -- ptr-preloaded-source )
	thread preloaded_source
		da source_context
		da load
		da cell_size
		da push_add
		da return

	; ( -- ptr-word-pair )
	declare "current-word"
	thread current_word
		da source_context
		da load
		da literal
		dq 8 * 2
		da push_add
		da return

	; ( -- ptr-line-start )
	declare "line-start"
	thread line_start
		da source_context
		da load
		da literal
		dq 8 * 4
		da push_add
		da return

	; ( -- )
	thread init_source_context
		da source_context_stack
		da source_context
		da store
		da clear_source_context
		da return

	; ( -- )
	thread clear_source_context
		da zero
		da line_size
		da store

		da zero
		da preloaded_source
		da store

		da zero
		da zero
		da current_word
		da store_pair

		da zero
		da line_start
		da store

		da return

	; ( -- )
	thread push_source_context
		da source_context
		da copy
		da load
		da literal
		dq source_context_cells * 8
		da push_add
		da swap
		da store
		da clear_source_context
		da return

	; ( -- )
	thread pop_source_context
		da am_initing
		da load
		branch_to .not_init

		da preloaded_source
		da load
		da free_pages
		da push_is_zero
		maybe break

		.not_init:
		da source_context
		da copy
		da load
		da literal
		dq source_context_cells * 8
		da push_subtract
		da swap
		da store
		da return

	; ( -- nested? )
	thread is_nested_source
		da source_context
		da load
		da source_context_stack
		da push_is_neq
		da return

	; ( bytes -- )
	declare "arena-allocate"
	thread arena_allocate
		da arena_top
		da load
		da push_add
		da arena_top
		da store
		da return

	; ( string length -- )
	;
	; A good candidate to be moved to init.si
	declare "include"
	thread include
		da copy_pair
		da stash
		da stash
		da drop
		da open_file
		da copy
		branch_to .found
		da status_script_not_found
		da print
		da unstash
		da unstash
		da print_line
		da drop
		da soft_fault

		.found:
		da unstash
		da unstash
		da drop_pair
		da set_up_preloaded_source
		da return

	; ( -- string length )
	declare "core-lib-src"
	thread core_lib_src
		da literal
		da core_lib
		da literal
		dq core_lib_end - core_lib
		da return

	declare "0"
	constant zero, 0

	declare "-1"
	constant all_ones, ~0

	declare "1"
	constant one, 1

	declare "cell-size"
	constant cell_size, 8

	declare "10"
	constant ten, 10

	declare "bss-size"
	constant bss_size, end_bss - begin_bss

	declare "rdata-size"
	constant rdata_size, end_rdata - begin_rdata

	declare "text-size"
	constant text_size, end_text - begin_text

	; Begin interpreter state variables

	declare "dictionary"
	variable dictionary, 1

	variable arena_top, 1
	variable should_exit, 1
	variable source_context, 1
	variable am_initing, 1

	; End interpreter state variables

	declare "arena-base"
	variable arena_base, arena_size / 8

	declare "is-assembling"
	variable is_assembling, 1

	declare "current-definition"
	variable current_definition, 1

	variable stdin_handle, 1
	variable stdout_handle, 1
	variable term_buffer, (term_buffer_size / 8) + 1 ; +1 to ensure null-termination
	variable string_a, 2
	variable string_b, 2
	variable parsed_number, 2
	variable source_context_stack, source_context_stack_depth * source_context_cells

	; A short discussion on dealing with errors (the red ones): if they occur in the uppermost context, we can
	; differentiate between a soft fault and a hard fault. A soft fault can be a non-existent word used in assembly
	; mode, which we could recover from by abandoning the current definition and flushing the line. A hard fault would
	; necessitate a full interpreter state reset, such as a stack underflow, since unknown but faulty code has been
	; executed. In a nested context, however, there is no meaningful way to recover from a soft fault, other than to
	; abandon all nested contexts (think of it as an uber-line-flush). If the topmost context is a piped input, we
	; should probably just exit either way. Also need to have some sort of warning message for when a fault occurs
	; during the init script, methinks.

	string status_overfull, yellow(`Line overfull\n`) ; not a fault, dealt with in terminal subsystem
	string status_unknown, red(`Unknown word: `) ; soft fault
	string status_stacks_unset, yellow(`Stacks were not cleared, or have underflowed\nPress enter to exit...\n`)
	string status_word_too_long, red(`Word is too long for dictionary entry\n`) ; soft fault
	string status_source_not_loaded, red(`Source file could not be read into memory\n`) ; soft fault
	string status_script_not_found, red(`Script not found: `) ; soft fault
	string status_no_word, red(`Input was cancelled before word was named\n`) ; soft fault
	string status_abort, yellow(`Aborted and restarted\n`)
	string status_bad_init, yellow(`Fault during core lib load\nPress enter to exit...\n`)
	string status_nested_def, red(`Cannot define new words while another is still being defined\n`) ; soft fault
	string newline, `\n`
	string negative, `-`

	declare "seq-clear"
	string seq_clear, vt_clear

	declare "seq-yellow"
	string seq_yellow, vt_yellow

	declare "seq-red"
	string seq_red, vt_red

	declare "seq-default"
	string seq_default, vt_default

	declare "seq-clear-scrollback"
	string seq_clear_scrollback, vt_clear_scrollback

	declare "version-string"
	string version_banner, cyan(version_string)

	%ifndef standalone
		kernel32:
			db `kernel32.dll\0`

		name ExitProcess
		name GetStdHandle
		name WriteFile
		name ReadFile
		name CreateFileA
		name SetFilePointer
		name CloseHandle
		name VirtualAlloc
		name VirtualFree
	%endif

	core_lib:
		%include "core.inc"
	
	core_lib_end:
		db 0

	align 8

section .bss
	align 8
	%ifndef standalone
		get_module_handle:
			resq 1

		get_proc_address:
			resq 1

		table_imports:
			resq n_imports
	%endif

	data_stack:
		resq stack_depth

	return_stack:
		resq stack_depth

commit_dictionary

section .text
	end_text:

section .rdata
	end_rdata:

section .bss
	end_bss:
