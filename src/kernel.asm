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

%define repl_buffer_size 512
%define assembly_arena_size 1024 * 1024
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
%define vt_clear_all `\x1b[H\x1b[J`
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
	%define id_GetConsoleMode 9
	%define id_WaitForSingleObject 10
	%define n_imports 11

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
	extern GetConsoleMode
	extern WaitForSingleObject
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
		lea tp, initialize
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
	declare "exit-process"
	code exit_process
		mov rcx, [dp]
		call_import ExitProcess

	; ( -- )
	declare "clear-data-stack"
	code clear_data_stack
		lea dp, stack_base(data_stack)
		next

	; ( -- )
	declare "clear-return-stack"
	code clear_return_stack
		lea rp, stack_base(return_stack)
		next

	; ( -- dp )
	declare "get-data-stack"
	code get_data_stack
		mov rax, dp
		sub dp, 8
		mov [dp], rax
		next

	; ( -- rp )
	declare "get-return-stack"
	code get_return_stack
		sub dp, 8
		mov [dp], rp
		next

	; ( value -- )
	declare "drop"
	code drop
		add dp, 8
		next

	; ( -- value )
	declare "literal"
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
	declare "get-std-handle"
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
	code stack_sub
		mov rax, [dp]
		add dp, 8
		sub [dp], rax
		next

	; ( condition -- )
	declare "branch"
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
	code stack_lt0
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
	code stack_eq0
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
	code stack_neq0
		mov rax, [dp]
		test rax, rax
		jnz .all_ones
		mov qword [dp], 0
		next

		.all_ones:
		mov qword [dp], ~0
		next

	; ( -- )
	declare "jump"
	code jump
		mov rax, [tp]
		lea tp, [tp + rax + 8]
		next

	; ( a b -- (a + b) )
	declare "+"
	code stack_add
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
	code stack_neq
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
	code stack_eq
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
	declare "push"
	code stack_push
		mov rax, [dp]
		add dp, 8
		sub rp, 8
		mov [rp], rax
		next

	; ( -- value )
	declare "pop"
	code stack_pop
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
	code stack_not
		not qword [dp]
		next

	; ( a b -- (a & b) )
	declare "&"
	code stack_and
		mov rax, [dp]
		add dp, 8
		and [dp], rax
		next

	; ( condition -- )
	declare "predicated"
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
	code stack_udiv
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		div rbx
		mov [dp], rax
		next

	; ( a b -- (a % b) )
	declare "u%"
	code stack_umod
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		div rbx
		mov [dp], rdx
		next

	; ( a b -- (a / b) )
	declare "/"
	code stack_div
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		idiv rbx
		mov [dp], rax
		next

	; ( a b -- (a % b) )
	declare "%"
	code stack_mod
		mov rax, [dp + 8]
		mov rbx, [dp]
		add dp, 8
		xor rdx, rdx
		idiv rbx
		mov [dp], rdx
		next

	; ( n -- -n )
	declare "0-"
	code stack_neg
		neg qword [dp]
		next

	; ( a b -- (a >= b) )
	declare ">="
	code stack_gte
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
	code stack_lte
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
	code stack_gt
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
	code stack_lt
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
	code stack_umul
		mov rax, [dp]
		add dp, 8
		mul qword [dp]
		mov [dp], rax
		next

	; ( a b -- (a * b) )
	declare "*"
	code stack_mul
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
	code stack_or
		mov rax, [dp]
		add dp, 8
		or [dp], rax
		next

	; ( -- )
	declare "maybe"
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
		mov rdx, 0x80000000 ; GENERIC_READ
		xor r8, r8
		xor r9, r9
		mov qword [rsp + 8 * 4], 3 ; OPEN_EXISTING
		mov qword [rsp + 8 * 5], 0x80 ; FILE_ATTRIBUTE_NORMAL
		mov qword [rsp + 8 * 6], r9
		call_import CreateFileA
		cmp rax, -1
		jne .success
		mov rax, 0

		.success:
		mov [dp], rax
		next

	; ( c-string -- handle )
	declare "create-file"
	code create_file
		mov rcx, [dp]
		mov rdx, 0x40000000 ; GENERIC_WRITE
		xor r8, r8
		xor r9, r9
		mov qword [rsp + 8 * 4], 2 ; CREATE_ALWAYS
		mov qword [rsp + 8 * 5], 0x80 ; FILE_ATTRIBUTE_NORMAL
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
	declare "peek"
	code stack_peek
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

	declare "init-imports"
	code init_imports
		%ifndef standalone
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
			get_import GetConsoleMode
			get_import WaitForSingleObject
		%endif
		next

	; ( handle -- is-console? )
	declare "check-is-console-handle"
	code check_is_console_handle
		mov rcx, [dp]
		lea rdx, [rsp + 8 * 4]
		call_import GetConsoleMode
		xor rcx, rcx
		test rax, rax
		jz .failure
		not rcx

		.failure:
		mov [dp], rcx
		next

	; ( value shift -- shifted )
	declare "<<"
	code stack_shl
		mov rcx, [dp]
		add dp, 8
		shl qword [dp], cl
		next

	; ( value shift -- shifted )
	declare ">>"
	code stack_shr
		mov rcx, [dp]
		add dp, 8
		shr qword [dp], cl
		next

	; ( value -- ++value )
	declare "1+"
	code stack_inc
		add qword [dp], 1
		next

	; ( handle -- )
	declare "await"
	code await
		mov rcx, [dp]
		xor rdx, rdx
		not rdx
		call_import WaitForSingleObject
		int3
		add dp, 8
		next

section .rdata
	align 8

	; This is here purely to make disassembly work properly
	declare "interpreter"
	thread interpreter

	initialize:
		da clear_data_stack
		da clear_return_stack
		da init_imports
		da init_handles
		da init_assembler
		da init_source_context_stack
		da init_dictionary
		da init_assembly_arena
		da init_terminal
		da init_logging

		da load_core_library

	interpret:
		da should_exit
		da load
		branch_to .exit

		da check_no_underflow
		maybe report_underflow

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
		da stack_not
		da is_assembling
		da load
		da stack_neq0
		da stack_and
		predicated assemble, invoke
		jump_to interpret

		.source_ended:
		da source_is_nested
		da stack_not
		branch_to .exit
		da source_pop
		da zero
		da is_initializing
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
		da stack_not
		branch_to interpret
		da assemble_literal
		da assemble
		jump_to interpret

	; ( -- underflow? )
	declare "check-no-underflow?"
	thread check_no_underflow
		da get_data_stack
		da data_stack_base
		da stack_gt
		da get_return_stack
		da cell_size
		da stack_add
		da return_stack_base
		da stack_gt
		da stack_or
		da return

	; ( -- )
	declare "report-underflow"
	thread report_underflow
		da status_underflow
		da print
		da get_current_word
		da stack_add
		da source_line_start
		da load
		da stack_sub
		da source_line_start
		da load
		da swap
		da print_line
		da clear_data_stack
		da clear_return_stack
		da soft_fault

	; ( -- )
	declare "init-terminal"
	thread init_terminal
		da zero
		da repl_buffer
		da store_byte

		da stdin_handle
		da load
		da check_is_console_handle
		da stack_not
		da is_terminal_piped
		da store

		da return

	; ( -- )
	declare "soft-fault"
	thread soft_fault
		da source_is_nested
		da is_terminal_piped
		da load
		da stack_or
		maybe hard_fault
		da flush_line

		da is_assembling
		da load
		da stack_not
		branch_to .exit
		da current_definition
		da load
		da assembly_arena_top
		da store

		.exit:
		da init_assembler
		da clear_return_stack
		jump_to interpret

	; ( -- )
	declare "init-assembler"
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
		da is_terminal_piped
		da load
		branch_to .piped

		da is_initializing
		da load
		branch_to .die
		da status_abort
		da print_line
		jump_to initialize

		.die:
		da status_bad_init
		da print_line
		da repl_read_line
		da all_ones
		da exit_process

		.piped:
		da status_fatal
		da print_line
		da all_ones
		da exit_process

	; ( -- )
	declare "load-core-library"
	thread load_core_library
		da literal
		da core_lib
		da source_push_buffer
		da all_ones
		da is_initializing
		da store
		da return

	; ( path -- buffer? length? )
	declare "load-file"
	thread load_file
		da open_file
		da copy
		branch_to .found
		da drop
		da zero
		da zero
		da return

		.found:
		da copy
		da stack_push
		da file_handle_load_content
		da stack_pop
		da close_handle
		da return

	; ( buffer -- )
	declare "source-push-buffer"
	thread source_push_buffer
		da source_push

		da copy
		da source_full_text
		da store

		da copy
		da zero
		da source_current_word
		da store_pair

		da copy
		da source_line_start
		da store

		da set_line_size
		da return

	; ( handle -- source? length? )
	declare "file-handle-load-content"
	thread file_handle_load_content
		da copy
		da stack_push
		da file_size
		da copy
		da all_ones
		da stack_neq
		branch_to .allocate
		da drop
		da stack_pop
		da drop
		jump_to .failed

		.allocate:
		da copy
		da load_length
		da store
		da copy
		da one
		da stack_add
		da allocate_pages
		da copy
		da stack_neq0
		branch_to .read
		da drop_pair
		da stack_pop
		da drop
		jump_to .failed

		.read:
		da copy
		da stack_pop
		da swap
		da stack_push
		da stack_push
		da swap
		da stack_pop
		da read_file
		da nip
		branch_to .succeeded
		da stack_pop
		da free_pages
		da drop
		jump_to .failed

		.succeeded:
		da stack_pop
		da load_length
		da load
		da return

		.failed:
		da status_file_handle_load_failure
		da print_line
		da soft_fault

	; ( handle -- size? )
	;
	; We treat -1 as an error sentinel
	declare "file-size"
	thread file_size
		da copy
		da zero
		da two
		da set_file_ptr
		da copy
		da all_ones
		da stack_eq
		branch_to .exit

		da swap
		da zero
		da zero
		da set_file_ptr
		da swap
		da over
		da all_ones
		da stack_neq
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
	declare "init-handles"
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

	; ( -- length? )
	declare "term-read-line"
	thread term_read_line
		da input_buffer
		da load_pair
		da stdin_handle
		da load
		da read_file
		da drop
		da zero
		da over
		da input_buffer
		da load
		da stack_add
		da store_byte
		da two
		da stack_sub
		da return

	; ( -- length? )
	declare "pipe-read-line"
	thread pipe_read_line
		da input_buffer
		da load

		.again:
		da copy
		da one
		da stdin_handle
		da load
		da read_file
		da drop

		da copy
		da stack_eq0
		branch_to .eof

		da over
		da stack_add
		da swap
		da load_byte
		da newline_code
		da stack_eq
		branch_to .exit
		da copy
		da input_buffer
		da load
		da stack_sub
		da input_buffer
		da load_2nd
		da stack_lt
		branch_to .again

		.exit:
		da input_buffer
		da load
		da stack_sub
		da two
		da stack_sub
		da return

		.eof:
		da drop_pair
		da all_ones
		da return

	; ( -- )
	declare "repl-read-line"
	thread repl_read_line
		da repl_buffer
		da literal
		dq repl_buffer_size
		da input_buffer
		da store_pair
		da read_line
		da source_line_size
		da store
		da return

	; ( -- length? )
	;
	; length? will be a signed negative number on failure
	declare "read-line"
	thread read_line
		.rewrite_point:
		da literal
		da .rewrite_point
		da is_terminal_piped
		da load
		branch_to .pipe
		da literal
		da term_read_line
		jump_to .rewrite

		.pipe:
		da literal
		da pipe_read_line

		.rewrite:
		da over
		da store
		da literal
		da return
		da swap
		da cell_size
		da stack_add
		da store
		jump_to .rewrite_point

	; ( -- exit? )
	declare "repl-accept-line-interactive-nolog"
	thread repl_accept_line_interactive_nolog
		da reset_current_word
		da repl_buffer
		da source_line_start
		da store

		.again:
		da repl_read_line

		da source_line_size
		da load

		da copy
		da stack_lt0
		branch_to .eof

		da stack_eq0
		branch_to .again

		da term_check_is_buffer_full
		branch_to .line_overfull

		da zero
		da return

		.line_overfull:
		da status_overfull
		da print_line

		.flush:
		da repl_read_line
		da term_check_is_buffer_full
		branch_to .flush
		jump_to .again

		.eof:
		da drop
		da all_ones
		da return

	; ( -- exit? )
	declare "repl-accept-line-interactive"
	thread repl_accept_line_interactive
		da repl_accept_line_interactive_nolog
		da copy
		maybe return
		da source_line_start
		da load
		da source_line_size
		da load
		da two
		da stack_add
		da log_file_handle
		da load
		da write_file
		maybe return
		da status_log_failure
		da print_line
		da repl_read_line
		da all_ones
		da exit_process

	; ( -- )
	declare "init-logging"
	thread init_logging
		da log_file_handle ; Might be post-restart
		da load
		da copy
		da stack_neq0
		predicated close_handle, drop

		da log_name
		da drop
		da create_file
		da copy
		da all_ones
		da stack_eq
		branch_to .error
		da log_file_handle
		da store
		da return

		.error:
		da status_log_failure
		da print_line
		da repl_read_line
		da all_ones
		da exit_process

	; ( string length -- )
	declare "print-line"
	thread print_line
		da print
		da new_line
		da return

	; ( -- overfull? )
	;
	; If the present line of input was longer than the buffer passed to ReadFile(), ReadFile() will notably _not_ place
	; a terminal newline, making it trivial to check for oversized lines.
	declare "term-buffer-too-small"
	thread term_check_is_buffer_full
		da repl_buffer
		da source_line_size
		da load
		da one
		da stack_add
		da stack_add
		da load_byte
		da newline_code
		da stack_neq
		da return

	; ( -- exit? )
	declare "accept-word"
	thread accept_word
		.again:
		da get_current_word
		da stack_add
		da copy

		da source_line_start
		da load
		da stack_sub
		da source_line_size
		da load
		da stack_eq
		branch_to .refill

		da consume_space
		da copy
		da load_byte
		da stack_eq0
		branch_to .refill
		da copy
		da consume_word
		da copy_pair
		da swap
		da stack_sub
		da nip

		da source_current_word
		da store_pair
		da zero
		da return

		.refill:
		da drop
		da repl_accept_line
		branch_to .exit
		jump_to .again

		.exit:
		da all_ones
		da return

	; ( -- exit? )
	;
	; The bottom-most source context reprsents the terminal, and so is identified with a zeroed source_full_text pointer
	declare "repl-accept-line"
	thread repl_accept_line
		da source_full_text
		da load
		predicated repl_accept_line_source_text, repl_accept_line_interactive
		da return

	; ( a b address -- )
	declare "store-pair"
	thread store_pair
		da copy
		da stack_push
		da cell_size
		da stack_add
		da store
		da stack_pop
		da store
		da return

	; ( address -- a b )
	declare "load-pair"
	thread load_pair
		da copy
		da cell_size
		da stack_add
		da stack_push
		da load
		da stack_pop
		da load
		da return

	; ( -- word length )
	declare "get-current-word"
	thread get_current_word
		da source_current_word
		da load_pair
		da return

	; ( -- )
	;
	; At all times, source_current_word refers to the address and length of the word that was just parsed for
	; interpretation.
	declare "reset-current-word"
	thread reset_current_word
		da repl_buffer
		da zero
		da source_current_word
		da store_pair
		da return

	; ( ptr -- new-ptr )
	;
	; Advances ptr past an initial run of whitespace characters
	declare "consume-space"
	thread consume_space
		.again:
		da copy
		da load_byte
		da check_is_space
		branch_to .advance
		da return

		.advance:
		da one
		da stack_add
		jump_to .again

	; ( ptr -- new-ptr )
	;
	; Advances ptr to the first space character after an initial run of non-space characters
	declare "consume-word"
	thread consume_word
		.again:
		da copy
		da load_byte
		da copy
		da stack_eq0
		branch_to .return
		da copy
		da check_is_space
		branch_to .return
		da drop
		da one
		da stack_add
		jump_to .again

		.return:
		da drop
		da return

	; ( char -- space? )
	;
	; Here's the issue: accept_word functionally implements the regex `[ \n\r\t]*([^ \n\r\t]+)?`
	; Because of that, a whitespace-only line will just run away into eternity. As such, it needs to
	; be contractual that repl_accept_line will strip out empty lines.
	declare "check-is-space"
	thread check_is_space
		da copy
		da literal
		dq ` `
		da stack_eq
		branch_to .all_ones

		da copy
		da literal
		dq `\t`
		da stack_eq
		branch_to .all_ones

		da copy
		da literal
		dq `\r`
		da stack_eq
		branch_to .all_ones

		da copy
		da newline_code
		da stack_eq
		branch_to .all_ones

		da drop
		da zero
		da return

		.all_ones:
		da drop
		da all_ones
		da return

	; ( -- )
	declare "init-dictionary"
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
		da stack_push
		da drop_pair
		da stack_pop
		da copy
		da entry_immediate
		da swap
		da entry_data_ptr
		da return

	; ( entry -- data )
	declare "entry-data-ptr"
	thread entry_data_ptr
		da entry_name
		da stack_add
		da one
		da stack_add
		da cell_align
		da return

	; ( entry -- immediate? )
	declare "entry-immediate?"
	thread entry_immediate
		da cell_size
		da stack_add
		da load_byte
		da literal
		dq immediate
		da stack_and
		da stack_neq0
		da return

	; ( address -- aligned-address )
	declare "cell-align"
	thread cell_align
		da copy
		da literal
		dq 7
		da stack_and
		da cell_size
		da swap
		da stack_sub
		da literal
		dq 7
		da stack_and
		da stack_add
		da return

	; ( -- )
	;
	; The input layer of the interpreter is structured around having a current line of source text, stored at
	; `source_line_ptr`, and a current word within that line, stored at `source_current_word`. Line reads (or "refills")
	; are automatically triggered whenever `accept_word` reaches the end of the current line. Now, `accept_word` figures
	; out where to start reading from by adding the current word length to the current word pointer (essentially
	; skipping just past the current word), so the simplest way to "flush" the rest of the current line is to fudge the
	; current word length so that the result of that addition points to the end of the line.
	declare "flush-line"
	thread flush_line
		da get_current_word
		da drop
		da copy
		da source_line_start
		da load
		da stack_sub
		da source_line_size
		da load
		da swap
		da stack_sub
		da source_current_word
		da store_pair
		da return

	; ( -- )
	declare "report-leftovers"
	thread report_leftovers
		da status_stacks_unset
		da print_line
		da repl_read_line
		da return

	; ( char -- digit? )
	declare "check-is-digit"
	thread check_is_digit
		da copy
		da literal
		dq '0'
		da stack_gte
		da stack_push
		da literal
		dq `9`
		da stack_lte
		da stack_pop
		da stack_and
		da return

	; ( string length -- n number? )
	declare "parse-u#"
	thread parse_unumber
		da parsed_number
		da store_pair
		da zero
		da stack_push

		.again:
		da parsed_number
		da load
		da load_byte
		da copy
		da check_is_digit
		da stack_not
		branch_to .nan
		da literal
		dq '0'
		da stack_sub
		da stack_pop
		da ten
		da stack_umul
		da stack_add
		da stack_push

		da parsed_number
		da load
		da one
		da stack_add
		da parsed_number
		da load_2nd
		da one
		da stack_sub
		da copy
		da stack_push
		da parsed_number
		da store_pair
		da stack_pop
		branch_to .again

		da stack_pop
		da all_ones
		da return

		.nan:
		da stack_pop
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
		da stack_eq
		branch_to .negative
		da parse_unumber
		da return

		.negative:
		da copy
		da one
		da stack_eq
		branch_to .nan
		da one
		da stack_sub
		da swap
		da one
		da stack_add
		da swap
		da parse_unumber
		da swap
		da stack_neg
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
		da stack_eq0
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
		da stack_gte
		branch_to .too_long
		da cell_align_assembly_arena
		da assembly_ptr
		da stack_push
		da dictionary
		da load
		da assemble
		da copy
		da assemble_byte
		da assemble_blob
		da zero
		da assemble_byte
		da cell_align_assembly_arena
		da stack_pop
		da return

		.too_long:
		da drop_pair
		da stack_pop
		da drop
		da status_word_too_long
		da print_line
		da soft_fault

		.rejected:
		da status_no_word
		da print_line
		da soft_fault

	; ( -- )
	declare "cell-align-assembly_arena"
	thread cell_align_assembly_arena
		da assembly_arena_top
		da load
		da cell_align
		da copy
		da assembly_arena_check_bounds
		da assembly_arena_top
		da store
		da return

	; ( cell -- )
	declare "assemble"
	thread assemble
		da assembly_ptr
		da cell_size
		da assembly_arena_allocate
		da store
		da return

	; ( byte -- )
	declare "assemble-byte"
	thread assemble_byte
		da assembly_ptr
		da one
		da assembly_arena_allocate
		da store_byte
		da return

	; ( new-ptr -- )
	declare "assembly-arena-check-bounds"
	thread assembly_arena_check_bounds
		da assembly_arena
		da stack_sub
		da literal
		dq assembly_arena_size
		da stack_lte
		branch_to .ok
		da status_assembly_bounds
		da print_line
		da hard_fault

		.ok:
		da return

	; ( -- )
	;
	; The disassembler assumes that every word in the arena or dictionary is immediately followed by another entry,
	; which always starts with a pointer to the previous word.
	declare "assembly-arena-start-block"
	thread assembly_arena_start_block
		da dictionary
		da load
		da assemble
		da return

	; ( byte-ptr length -- )
	declare "assemble-blob"
	thread assemble_blob
		da assembly_ptr
		da over
		da assembly_arena_allocate
		da copy_blob
		da return

	; ( -- )
	declare "init-assembly_arena"
	thread init_assembly_arena
		da assembly_arena
		da assembly_arena_top
		da store
		da return

	; ( -- )
	declare "immediate"
	thread make_immediate
		da dictionary
		da load
		da cell_size
		da stack_add
		da copy
		da load_byte
		da literal
		dq immediate
		da stack_or
		da swap
		da store_byte
		da return

	; ( -- ptr )
	declare "assembly-arena-ptr"
	thread assembly_ptr
		da assembly_arena_top
		da load
		da return

	; ( -- word? )
	declare "find:"
	thread find_next_word
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
	declare "repl-accept-line-source-text"
	thread repl_accept_line_source_text
		da get_current_word
		da stack_add

		da copy
		da load_byte
		branch_to .next_line
		da drop
		da all_ones
		da return

		.again:
		da one
		da stack_add

		.next_line:
		da copy
		da load_byte
		da check_is_space
		branch_to .again

		da copy
		da zero
		da source_current_word
		da store_pair

		da copy
		da source_line_start
		da store
		da set_line_size
		da zero
		da return

	; ( line-ptr -- )
	;
	; For terminal input, ReadFile() already reports the length of the line due to the console-specific behavior around
	; newlines, but for in-memory source files, we have to count bytes ourselves.
	declare "set-line-size"
	thread set_line_size
		da copy

		.again:
		da copy
		da load_byte
		da literal ; Assumes CRLF line endings :(
		dq `\r`
		da stack_eq
		branch_to .found_line_end
		da copy
		da load_byte
		da stack_eq0
		branch_to .found_line_end
		da one
		da stack_add
		jump_to .again

		.found_line_end:
		da swap
		da stack_sub
		da source_line_size
		da store
		da return

	; The context stack should be bounds-checked; `execute` should report if recursion depth has been exceeded

	; ( -- ptr-line-size )
	declare "line-size"
	thread source_line_size
		da source_context
		da load
		da return

	; ( -- ptr-preloaded-source )
	declare "full-text"
	thread source_full_text
		da source_context
		da load
		da cell_size
		da stack_add
		da return

	; ( -- ptr-word-pair )
	declare "current-word"
	thread source_current_word
		da source_context
		da load
		da literal
		dq 8 * 2
		da stack_add
		da return

	; ( -- ptr-line-start )
	declare "line-start"
	thread source_line_start
		da source_context
		da load
		da literal
		dq 8 * 4
		da stack_add
		da return

	; ( -- )
	declare "init-source-context-stack"
	thread init_source_context_stack
		da source_context_stack
		da source_context
		da store
		da source_clear
		da return

	; ( -- )
	;
	; You'd be surprised at the kind of bugs that crop up if source contexts are not explicitly zeroed; a symptom of
	; over-reliance on the zeroing behavior of BSS sections.
	declare "source-clear"
	thread source_clear
		da zero
		da source_line_size
		da store

		da zero
		da source_full_text
		da store

		da zero
		da zero
		da source_current_word
		da store_pair

		da zero
		da source_line_start
		da store

		da return

	; ( -- )
	declare "source-push"
	thread source_push
		da source_context
		da copy
		da load
		da literal
		dq source_context_cells * 8
		da stack_add
		da swap
		da store
		da source_clear
		da return

	; ( -- )
	declare "source-pop"
	thread source_pop
		da is_initializing
		da load
		branch_to .not_init

		da source_full_text
		da load
		da free_pages
		da stack_eq0
		maybe break

		.not_init:
		da source_context
		da copy
		da load
		da literal
		dq source_context_cells * 8
		da stack_sub
		da swap
		da store
		da return

	; ( -- nested? )
	declare "source-is-nested"
	thread source_is_nested
		da source_context
		da load
		da source_context_stack
		da stack_neq
		da return

	; ( bytes -- )
	declare "assembly-arena-allocate"
	thread assembly_arena_allocate
		da assembly_arena_top
		da load
		da stack_add
		da copy
		da assembly_arena_check_bounds
		da assembly_arena_top
		da store
		da return

	; ( string length -- )
	;
	; A good candidate to be moved to init.si. `execute` is how we do raw interpretation of an on-disk script; the
	; high-level flow is that the file is opened, read into memory, null-terminated, then pushed onto the source context
	; stack. As soon as `execute` returns to the interpreter (note that this means it will behave very strangely within
	; a definition), the interpreter will continue reading from the in-memory source. When it reaches EOF, it pops the
	; source context, restoring the original one, with the rest of the line after the `execute` still intact.
	declare "execute"
	thread execute
		da copy_pair
		da stack_push
		da stack_push
		da drop
		da load_file
		branch_to .found
		da status_script_not_found
		da print
		da stack_pop
		da stack_pop
		da print_line
		da drop
		da soft_fault

		.found:
		da stack_pop
		da stack_pop
		da drop_pair
		da source_push_buffer
		da return

	; ( -- not-empty? )
	declare "test-stacks"
	thread test_stacks
		da get_data_stack
		da data_stack_base
		da stack_eq
		da get_return_stack
		da cell_size
		da stack_add
		da return_stack_base
		da stack_eq
		da stack_and
		da stack_not
		da return

	declare "0"
	constant zero, 0

	declare "-1"
	constant all_ones, ~0

	declare "1"
	constant one, 1

	declare "2"
	constant two, 2

	declare "cell-size"
	constant cell_size, 8

	declare "10"
	constant ten, 10

	declare "newline-code"
	constant newline_code, `\n`

	declare "data-stack-base"
	constant data_stack_base, address(stack_base(data_stack))

	declare "return-stack-base"
	constant return_stack_base, address(stack_base(return_stack))

	declare "bss-size"
	constant bss_size, end_bss - begin_bss

	declare "rdata-size"
	constant rdata_size, end_rdata - begin_rdata

	declare "text-size"
	constant text_size, end_text - begin_text

	declare "ptr-invoke-thread"
	constant ptr_invoke_thread, address(invoke_thread)

	; Begin interpreter state variables

	declare "dictionary"
	variable dictionary, 1

	declare "assembly-arena-top"
	variable assembly_arena_top, 1

	declare "should-exit"
	variable should_exit, 1

	declare "source-context"
	variable source_context, 1

	declare "is-initializing"
	variable is_initializing, 1

	; End interpreter state variables

	declare "assembly-arena-base"
	variable assembly_arena, assembly_arena_size / 8

	declare "is-assembling"
	variable is_assembling, 1

	declare "current-definition"
	variable current_definition, 1

	declare "stdin-handle"
	variable stdin_handle, 1

	declare "stdout-handle"
	variable stdout_handle, 1

	declare "repl-buffer"
	variable repl_buffer, (repl_buffer_size / 8) + 1 ; +1 to ensure null-termination

	declare "string-a"
	variable string_a, 2

	declare "string-b"
	variable string_b, 2

	declare "parsed-number"
	variable parsed_number, 2

	declare "source-context-stack"
	variable source_context_stack, source_context_stack_depth * source_context_cells

	declare "is-terminal-piped"
	variable is_terminal_piped, 1

	declare "log-file-handle"
	variable log_file_handle, 1

	; TODO: refactor file_handle_load_content; this is kind of hacky and indicative of its overcomplexity
	declare "load-length"
	variable load_length, 1

	declare "input-buffer"
	variable input_buffer, 2 ; buffer, length

	; A short discussion on dealing with errors (the red ones): if they occur in the uppermost context, we can
	; differentiate between a soft fault and a hard fault. A soft fault can be a non-existent word used in assembly
	; mode, which we could recover from by abandoning the current definition and flushing the line. A hard fault would
	; necessitate a full interpreter state reset, such as a stack underflow, since unknown but faulty code has been
	; executed. In a nested context, however, there is no meaningful way to recover from a soft fault, other than to
	; abandon all nested contexts (think of it as an uber-line-flush). If the topmost context is a piped input, we
	; should probably just exit either way. Also need to have some sort of warning message for when a fault occurs
	; during the init script, methinks.

	declare "status-overfull"
	string status_overfull, yellow(`Line overfull\n`) ; not a fault, dealt with in terminal subsystem

	declare "status-unknown"
	string status_unknown, red(`Unknown word: `) ; soft fault

	declare "status-stacks-unset"
	string status_stacks_unset, yellow(`Stacks were not cleared, or have underflowed\nPress enter to exit...\n`)

	declare "status-word-too-long"
	string status_word_too_long, red(`Word is too long for dictionary entry\n`) ; soft fault

	declare "status-file-handle-load-failure"
	string status_file_handle_load_failure, red(`File contents could not be read into memory\n`) ; soft fault

	declare "status-script-not-found"
	string status_script_not_found, red(`Script not found: `) ; soft fault

	declare "status-no-word"
	string status_no_word, red(`Input was cancelled before word was named\n`) ; soft fault

	declare "status-abort"
	string status_abort, yellow(`Aborted and restarted\n`)

	declare "status-bad-init"
	string status_bad_init, yellow(`Fault during core lib load\nPress enter to exit...\n`)

	declare "status-nested-def"
	string status_nested_def, red(`Cannot define new words while another is still being defined\n`) ; soft fault

	declare "status-non-interactive"
	string status_non_interactive, red(`Cannot accept input from non-interactive terminal\n`) ; fatal error

	declare "status-log-failure"
	string status_log_failure, red(`Log related-failure\nPress enter to exit...`) ; fatal error

	declare "status-fatal"
	string status_fatal, red(`Hard fault during piped input\n`) ; fatal error

	declare "status-underflow"
	string status_underflow, red(`Stack underflow detected after: `) ; soft fault

	declare "status-assembly-arena-bounds"
	string status_assembly_bounds, red(`Assembly arena bounds exceeded\n`) ; hard fault

	declare "newline-char"
	string newline, `\n`

	declare "negative"
	string negative, `-`

	declare "log-name"
	string log_name, `log.si`

	declare "seq-clear"
	string seq_clear, vt_clear

	declare "seq-yellow"
	string seq_yellow, vt_yellow

	declare "seq-red"
	string seq_red, vt_red

	declare "seq-cyan"
	string seq_cyan, vt_cyan

	declare "seq-default"
	string seq_default, vt_default

	declare "seq-clear-all"
	string seq_clear_all, vt_clear_all

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
		name GetConsoleMode
		name WaitForSingleObject
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
