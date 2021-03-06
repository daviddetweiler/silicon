; If you want to learn more, I suggest you read the book "Threaded Interpretive Languages."

; Long-term goals (some of these are mutually exclusive):
;   - Provide an ANSI Forth environment in here (as in, data_stack an official test suite)
;   - Provide a self-hosting metacompiler version of it, throw away the assembly
;   - Implement a variety of interesting languages:
;       - Write a Windows x64 assembler
;           - Possibly reimplement the TIL kernel in this assembly language
;           - Folds into writing a generally useful PE linker, or some custom loader (see other languages)
;       - Lisp (probably Scheme, and both source and image-based)
;       - Smalltalk (duh)

bits 64

global start

extern ExitProcess
extern GetStdHandle
extern WriteFile
extern ReadFile
extern VirtualAlloc
extern CreateFileA

%define line_buffer_size 128
%define token_max_len 64

%assign latest_header 0
%define header_0 0

%macro make_header 1-2 false
	%define immediate_false 0
	%define immediate_true 0x80
	%assign next_header latest_header + 1
	%define header header_ %+ next_header

	align 8

header:
	db (%%link - header) | (immediate_ %+ %2)

%%name:
	db %1, 0
	align 8

%%link:
	dq header_ %+ latest_header

	%assign latest_header next_header
%endmacro

%macro make_word 2
	%1:
		dq %2
%endmacro

%macro make_code_word 1
	make_word %1, %1 + 8
%endmacro

%macro make_thread 1
	make_word %1, call_thread
%endmacro

%macro make_variable 1
	make_word %1, call_variable
%endmacro

%macro make_constant 1
	make_word %1, call_constant
%endmacro

%macro make_branch 1
	dq branch
	dq (%1 - %%next) / 8
	%%next:
%endmacro

%macro make_jump 1
	dq jump
	dq (%1 - %%next) / 8
	%%next:
%endmacro

; Runs the word referenced at the current IP, advances IP
%macro make_continue 0
	mov r13, [r12]
	add r12, 8
	make_run
%endmacro

; Runs a word, setting WA to point to the data field
%macro make_run 0
	add r13, 8
	jmp qword [r13 - 8]
%endmacro

section .text
	start:
		push r12
		push r13
		push r14
		push r15
		sub rsp, 0x88 ; Stack alignment + 16 parameters
		mov r12, thread
		mov r14, return_stack
		mov r15, data_stack
		make_continue

	; Procedure implementing threaded list-words
	call_thread:
		sub r14, 8
		mov [r14], r12
		mov r12, r13
		make_continue

	; Pushes the address of the word data field
	call_variable:
		sub r15, 8
		mov [r15], r13
		make_continue

	; Pushes the first cell of the word data field
	call_constant:
		mov rcx, [r13]
		sub r15, 8
		mov [r15], rcx
		make_continue

	make_header "create-file"
	make_code_word create_file
		mov rcx, [r15]
		mov rdx, (1 << 31 | 1 << 30)
		xor r8, r8
		xor r9, r9
		mov qword [rsp + 8 * 4], 2
		mov qword [rsp + 8 * 5], 128
		mov qword [rsp + 8 * 6], 0
		call CreateFileA
		mov [r15], rax
		make_continue

	; ( -- ) Returns return_stack from a thread
	make_code_word return
		mov r12, [r14]
		add r14, 8
		make_continue

	; ( -- ) Exits the host process
	make_code_word exit
		xor rcx, rcx
		call ExitProcess

	; ( word-address -- ) Executes the word at `word-address`
	make_code_word execute
		mov r13, [r15]
		add r15, 8
		make_run

	; ( -- value ) Where `value` is the value of the cell immediately following `literal` in the instruction stream.
	; `literal` resumes execution at the cell following it.
	make_code_word literal
		mov rcx, [r12]
		add r12, 8
		sub r15, 8
		mov [r15], rcx
		make_continue

	; ( id -- handle ) Retrieves the handle specified by `id`; see the Windows API documentation
	make_code_word get_std_handle
		mov rcx, [r15]
		call GetStdHandle
		mov [r15], rax
		make_continue

	; ( a -- )
	make_code_word drop
		add r15, 8
		make_continue

	; ( buffer bytes handle -- )
	make_header "write-handle"
	make_code_word write_handle
		mov rcx, [r15]
		mov rdx, [r15 + 16]
		mov r8, [r15 + 8]
		mov r9, r15
		mov qword [rsp + 8 * 4], 0
		call WriteFile
		add r15, 24
		make_continue

	; ( flag -- ) Expects a literal signed branch constant following it in the instruction stream; if `flag` is zero,
	; resumes execution after the constant, else it adjusts the IP by the branch offset in units of cells.
	make_code_word branch
		mov rcx, [r12]
		add r12, 8
		mov rdx, [r15]
		add r15, 8
		test rdx, rdx
		setne dl
		movzx rdx, dl
		imul rcx, rdx
		imul rcx, 8
		add r12, rcx
		make_continue

	; ( -- ) Similar to `branch`, but does not take a flag, and always jumps
	make_code_word jump
		mov rcx, [r12]
		add r12, 8
		imul rcx, 8
		add r12, rcx
		make_continue

	; ( buffer bytes handle -- filled ) Read bytes from `handle` into `buffer`; `filled` is the number of bytes actually
	; read
	make_code_word read_handle
		mov rcx, [r15]
		mov rdx, [r15 + 16]
		mov r8, [r15 + 8]
		mov r9, r15
		mov qword [rsp + 8 * 4], 0
		call ReadFile
		mov rcx, [r15]
		add r15, 16
		mov [r15], rcx
		make_continue

	; ( address -- byte ) Similar to `peek`, but only reads one byte, instead of a full cell
	make_header "b@"
	make_code_word peek_byte
		mov rcx, [r15]
		movzx rcx, byte [rcx]
		mov [r15], rcx
		make_continue

	; ( byte address -- ) Similar to `poke`, but only writes the first byte of `byte`
	make_header "b!"
	make_code_word poke_byte
		mov rcx, [r15]
		mov dl, byte [r15 + 8]
		mov byte [rcx], dl
		add r15, 16
		make_continue

	; ( a -- a a )
	make_header "dup"
	make_code_word copy
		mov rcx, [r15]
		sub r15, 8
		mov [r15], rcx
		make_continue

	; ( b a -- a b )
	make_header "swap"
	make_code_word swap
		mov rcx, [r15]
		xchg [r15 + 8], rcx
		mov [r15], rcx
		make_continue

	; ( b a -- a )
	make_code_word nip
		mov rcx, [r15]
		add r15, 8
		mov [r15], rcx
		make_continue

	; ( a -- ) Moves `a` onto the return stack
	make_header ">r"
	make_code_word push_cell
		mov rcx, [r15]
		add r15, 8
		sub r14, 8
		mov [r14], rcx
		make_continue

	; ( -- a ) Pops `a` from the return stack
	make_header "<r"
	make_code_word pop_cell
		mov rcx, [r14]
		add r14, 8
		sub r15, 8
		mov [r15], rcx
		make_continue

	make_code_word two_copy
		mov rcx, [r15]
		mov rdx, [r15 + 8]
		sub r15, 16
		mov [r15 + 8], rdx
		mov [r15], rcx
		make_continue

	make_code_word two_drop
		add r15, 16
		make_continue

	; ( b a -- mod ) mod = a % b
	make_code_word modulus
		xor rdx, rdx
		mov rax, [r15]
		add r15, 8
		div qword [r15]
		mov [r15], rdx
		make_continue

	; ( address -- *address )
	make_header "@"
	make_code_word peek
		mov rcx, [r15]
		mov rcx, [rcx]
		mov [r15], rcx
		make_continue

	; ( value address -- ) `*address = value`
	make_header "!"
	make_code_word poke
		mov rcx, [r15]
		mov rdx, [r15 + 8]
		mov [rcx], rdx
		add r15, 16
		make_continue

	; ( b a -- c ) c = a + b
	make_header "+"
	make_code_word stack_add
		mov rcx, [r15]
		add r15, 8
		add [r15], rcx
		make_continue

	; ( b a -- c ) c = a - b
	make_header "-"
	make_code_word stack_sub
		mov rcx, [r15]
		add r15, 8
		xchg [r15], rcx
		sub [r15], rcx
		make_continue

	; ( b a -- c ) c = a * b
	make_header "*"
	make_code_word stack_mul
		mov rax, [r15]
		add r15, 8
		mul qword [r15]
		mov [r15], rax
		make_continue

	; ( b a -- c ) c = a / b
	make_header "/"
	make_code_word stack_div
		xor rdx, rdx
		mov rax, [r15]
		add r15, 8
		div qword [r15]
		mov [r15], rax
		make_continue

	; ( b a -- c ) c = a == b
	make_code_word equals
		mov rcx, [r15]
		add r15, 8
		cmp rcx, [r15]
		sete cl
		movzx rcx, cl
		xor rdx, rdx
		not rdx
		imul rcx, rdx
		mov [r15], rcx
		make_continue

	; ( b a -- c ) c = a > b
	make_code_word greater_than
		mov rcx, [r15]
		add r15, 8
		cmp rcx, [r15]
		seta cl
		movzx rcx, cl
		xor rdx, rdx
		not rdx
		imul rcx, rdx
		mov [r15], rcx
		make_continue

	; ( a b -- c ) c = a | b
	make_header "|"
	make_code_word stack_or
		mov rcx, [r15]
		add r15, 8
		or [r15], rcx
		make_continue

	; ( a b -- c ) c = a & b
	make_header "&"
	make_code_word stack_and
		mov rcx, [r15]
		add r15, 8
		and [r15], rcx
		make_continue

	; ( a -- ~a )
	make_header "~"
	make_code_word stack_not
		mov rcx, [r15]
		not rcx
		mov [r15], rcx
		make_continue

	; ( a -- b ) b = a + 1
	make_code_word increment
		inc qword [r15]
		make_continue

	; ( a -- a==0 )
	make_code_word is_zero
		mov rcx, [r15]
		test rcx, rcx
		setz cl
		movzx rcx, cl
		xor rdx, rdx
		not rdx
		imul rcx, rdx
		mov [r15], rcx
		make_continue

	make_code_word is_digit
		mov r8, [r15]
		mov r9, r8
		cmp r8, "0"
		setl cl
		cmp r9, "9"
		setg dl
		or cl, dl
		movzx rcx, cl
		xor rdx, rdx
		not rdx
		imul rcx, rdx
		not rcx
		mov [r15], rcx
		make_continue

	make_code_word do_rdtsc
		sub r15, 8
		xor eax, eax
		cpuid
		rdtsc
		shl rdx, 32
		or rax, rdx
		mov [r15], rax
		make_continue

	make_code_word do_rdtscp
		rdtscp
		shl rdx, 32
		or rax, rdx
		sub r15, 8
		mov [r15], rax
		xor eax, eax
		cpuid
		make_continue

	make_code_word break
		int3
		make_continue

	make_code_word get_data_stack
		mov rcx, r15
		sub r15, 8
		mov [r15], rcx
		make_continue

	make_code_word alloc_rwe
		xor rcx, rcx
		mov rdx, [r15]
		mov r8, 0x00001000
		mov r9, 0x40
		call VirtualAlloc
		mov [r15], rax
		make_continue

section .rdata
	; The initial thread executed by `start`
	thread:
		dq init_io
		dq greet
		dq set_up_data_space
		dq interpret
		dq exit

	make_thread set_up_data_space
		dq literal
		dq 4096 * 16
		dq alloc_rwe
		dq free_ptr
		dq poke
		dq return

	; ( -- ) Set values of `stdin` and `stdout`
	make_thread init_io
		dq literal
		dq -11
		dq get_std_handle
		dq stdout
		dq poke
		dq literal
		dq -10
		dq get_std_handle
		dq stdin
		dq poke
		dq return

	; ( ch -- ) Write `ch` to `stdout`
	make_thread put
		dq stdout
		dq peek
		dq write_byte
		dq return

	; ( string -- ) Write `string` to `stdin`.
	make_header "print"
	make_thread print
		print_next:
			dq copy ; ( str -- str str )
			dq peek_byte ; ( str str -- str ch )
			dq copy ; ( str ch -- str ch ch )
			make_branch print_continue

		dq two_drop ; ( str ch -- )
		dq return
		print_continue:
			dq put ; ( str ch -- str )
			dq increment ; ( str -- str + 1 )
			make_jump print_next

	make_thread read_line
		dq literal
		dq line_buffer_size
		dq swap
		dq read_handle
		dq return

	; ( byte handle -- ) Writes the first byte of `byte` to `handle`
	make_thread write_byte
		dq push_cell ; byte R: handle
		dq get_data_stack ; byte &byte R: handle
		dq literal ; byte &byte 1 R: handle
		dq 1
		dq pop_cell ; byte &byte 1 handle
		dq write_handle ; byte
		dq drop
		dq return

	; ( -- !iseof ) Refills the line buffer from `stdin`, indicating if EOF has been reached. Note that we do not return
	; the standard `TRUE` / `FALSE` values, but the zero / non-zero expected by `branch`.
	make_thread refill
		dq line_buffer
		dq stdin
		dq peek
		dq read_line
		dq copy
		dq filled
		dq poke
		dq zero
		dq line_ptr
		dq poke
		dq true
		dq is_fresh_line
		dq poke
		dq return

	; ( -- ch ) `ch` is either the next character from stdin, or null on EOF
	make_thread key
		dq peek_char ; ( lb[iop] -- )
		dq next_char
		dq return

	; ( -- ch ) `ch` is either the next character from stdin, or null on EOF; does not advance the input pointer
	make_thread peek_char
		dq fill_if_empty ; ( -- !iseof )
		make_branch peek_char_read
		dq zero
		dq return
		peek_char_read:
			dq line_ptr ; ( &iop -- )
			dq peek ; ( iop -- )
			dq line_buffer ; ( iop &lb -- )
			dq stack_add ; ( &lb[iop] -- )
			dq peek_byte ; ( lb[iop] -- )
			dq return

	; ( -- ) Advances the input pointer
	make_thread next_char
		dq zero
		dq is_fresh_line
		dq poke
		dq line_ptr ; ( &iop -- )
		dq copy ; ( &iop &iop -- )
		dq peek ; ( &iop iop -- )
		dq increment ; ( &iop iop + 1 -- )
		dq swap ; ( iop + 1 &iop -- )
		dq poke ; ( -- )
		dq return

	; ( -- !iseof ) Conditional refill of the line_buffer, indicates an EOF condition. Returns a non-standard boolean.
	make_thread fill_if_empty
		dq filled
		dq peek
		make_branch fill_if_empty_fill
		dq zero
		dq return
		fill_if_empty_fill:
			dq is_fresh_line
			dq peek
			make_branch fill_if_empty_done

		dq filled ; ( &fill -- )
		dq peek ; ( fill -- )
		dq line_ptr ; ( fill &iop -- )
		dq peek ; ( fill iop -- )
		dq modulus ; ( iop%fill -- )
		make_branch fill_if_empty_done
		dq refill ; ( -- !iseof )
		dq return
		fill_if_empty_done:
			dq true
			dq return

	; ( -- ) Emits a newline
	make_header "cr"
	make_thread newline
		dq literal
		dq 10
		dq put
		dq return

	; ( string -- ) Prints `string` with a terminal newline.
	make_header "println"
	make_thread println
		dq print
		dq newline
		dq return

	; ( buffer -- token ) `token` points to the next null-terminated token
	make_thread get_token
		dq skip_space ; ( buf -- buf )
		dq zero ; ( buf -- buf 0 )
		dq token_ptr ; ( buf 0 -- buf 0 &i )
		dq poke ; ( buf 0 &i -- buf )
		get_token_loop:
			dq token_ptr
			dq peek
			dq literal
			dq token_max_len
			dq equals
			make_branch get_token_full

		dq key ; ( buf -- buf ch )
		dq copy ; ( buf ch -- buf ch ch )
		make_branch get_token_ok ; ( buf ch ch -- buf ch )
		dq two_drop ; ( buf ch -- )
		dq zero ; ( -- 0 )
		dq return ; ( 0 -- 0 )
		get_token_ok:
			dq two_copy ; ( buf ch -- buf ch buf ch )
			dq swap ; ( buf ch buf ch -- buf ch ch buf )
			dq token_ptr ; ( * &tp -- )
			dq copy ; ( * &tp &tp -- )
			dq peek ; ( * &tp tp -- )
			dq swap ; ( * tp &tp -- )
			dq copy ; ( * tp &tp &tp -- )
			dq peek ; ( * tp &tp tp -- )
			dq increment ; ( * tp &tp tp+1 -- )
			dq swap ; ( * tp tp+1 &tp -- )
			dq poke ; ( * buf tp -- )
			dq stack_add ; ( buf ch ch &buf[tp] -- )
			dq poke_byte ; ( buf ch -- )
			dq is_space ; ( buf sp -- )
			dq stack_not ; ( buf !sp -- )
			make_branch get_token_loop ; ( buf -- )

		dq copy ; ( buf buf -- )
		dq token_ptr ; ( buf buf &tp -- )
		dq peek ; ( buf buf tp -- )
		dq literal
		dq -1
		dq stack_add ; ( buf buf tp-1 -- )
		dq stack_add ; ( buf &buf[tp-1] -- )
		dq zero ; ( buf &buf[tp-1] 0 -- )
		dq swap
		dq poke_byte
		dq return
		get_token_full:
			dq copy
			dq zero
			dq swap
			dq poke_byte
			dq return

	make_header "next-token"
	make_thread get_repl_token
		dq repl_token_buffer
		dq get_token
		dq return

	; ( -- ) Skip whitespace in input buffer.
	make_thread skip_space
		skip_space_next:
			dq peek_char
			dq is_space
			make_branch skip_space_continue

		dq return
		skip_space_continue:
			dq next_char
			make_jump skip_space_next

	; ( ch -- sp ) sp = ch in ['\r', '\n', '\t', ' ']
	make_thread is_space
		dq copy ; ( ch ch -- )
		dq literal
		dq " "
		dq equals ; ( ch ch==' ' -- )
		dq swap ; ( ch==' ' ch -- )
		dq copy
		dq literal
		dq `\r`
		dq equals
		dq swap
		dq copy
		dq literal
		dq `\t`
		dq equals
		dq swap
		dq literal
		dq `\n`
		dq equals
		dq stack_or
		dq stack_or
		dq stack_or
		dq return

	make_header "variable"
	make_thread variable
		dq create_word
		dq literal
		dq call_variable
		dq compile_cell
		dq zero
		dq compile_cell
		dq return

	; This is the banner
	make_variable greeting
		db `Silicon (c) 2022 David Detweiler\n\n\0`

	; ( -- 0 )
	make_header "false"
	make_constant zero
		dq 0

	make_header "true"
	make_constant true
		dq 0ffffffffffffffffh

	make_variable not_a_word
		db ` is not a word\n\n\0`

	make_variable invalid_token
		db `token was too big\n\n\0`

	; ( -- ) Runs in a loop, consuming tokens, finding them in the dictionary, executing them, and purging the line on
	; error. Returns on EOF.
	;
	; Right now we suffer from an issue: our input method is more stream-oriented than line-oriented. This is quite
	; convenient to avoid dealing with buffer size issues (as we do need to deal with with tokenization), but it makes
	; end-of-line actions difficult, as the triggering newline will only be seen by skip_spaces inside of get_token.
	;
	; The flow is fairly simple: we read in a token. If this token is too long (marked by being empty), we say so and
	; purge the line. Then we try and interpret it as an unsigned decimal number (to_number). If we succeed, we push it
	; and continue. If we don't, we then look it up in the dictionary. If we found it, we invoke it and loop. If we
	; didn't, we print an error and purge the line. A compile mode could be implemented by a variable, which we then use
	; to determine what to do.
	make_thread interpret
		interpret_loop:
			dq token_buffer
			dq get_token ; ( -- token )
			dq copy ; ( token -- token token )
			make_branch interpret_token ; ( token token -- token )

		dq drop ; ( token -- )
		dq return ; ( -- )
		interpret_token:
			dq copy
			dq peek_byte
			make_branch interpret_valid_token

		dq invalid_token
		dq println
		dq purge_line
		make_jump interpret_loop
		interpret_valid_token:
			dq copy ; token token
			dq to_number ; token number?
			dq copy ; token number? number?
			dq true ; token number? number? true
			dq equals ; token number? not_number
			dq stack_not ; token number? !not_number
			make_branch interpret_number ; token number?

		dq drop	; token
		dq copy ; ( token -- token token )
		dq look_up ; ( token -- token word )
		dq copy ; ( token word -- token word word )
		make_branch interpret_word ; ( token word word -- token word )
		dq drop ; ( token word -- token )
		dq print ; ( token -- )
		dq not_a_word
		dq println
		dq purge_line
		make_jump interpret_loop
		interpret_number:
			dq nip
			dq compiling
			dq peek
			make_branch interpret_compile_number

		make_jump interpret_loop
		interpret_word:
			dq nip
			dq compiling
			dq peek
			make_branch interpret_compile_word

		interpret_execute_word:
			dq get_dict_token
			dq execute
			make_jump interpret_loop

		interpret_compile_word:
			dq copy
			dq get_dict_immediate
			make_branch interpret_execute_word
			dq get_dict_token
			dq compile_cell
			make_jump interpret_loop

		interpret_compile_number:
			dq literal
			dq literal
			dq compile_cell
			dq compile_cell
			make_jump interpret_loop

	make_thread compile_cell
		dq free_ptr ; cell &free
		dq peek ; cell free
		dq copy ; cell free free
		dq push_cell ; cell free R: free
		dq poke ; R: free
		dq pop_cell ; free
		dq cell_size ; free 8
		dq stack_add ; free+8
		dq free_ptr ; free+8 &free
		dq poke ;
		dq return

	make_thread compile_byte
		dq free_ptr ; cell &free
		dq peek ; cell free
		dq copy ; cell free free
		dq push_cell ; cell free R: free
		dq poke_byte ; R: free
		dq pop_cell ; free
		dq increment
		dq free_ptr ; free+1 &free
		dq poke ;
		dq return

	make_header '"'
	make_thread string
		dq free_ptr
		dq peek
		dq push_cell
		string_loop:
			dq key
			dq copy
			dq literal
			dq '"'
			dq equals
			make_branch string_done

		dq compile_byte
		make_jump string_loop	
		string_done:
			dq zero
			dq compile_byte
			dq drop
			dq pop_cell
			dq return

	; ( token -- n )
	make_thread to_number
		dq zero ; token 0
		to_number_loop:
			dq swap ; n token
			dq copy ; n token token
			dq increment ; n token token+1
			dq push_cell ; n token R: token+1
			dq peek_byte ; n *token R: token+1
			dq copy	; n *token *token R: token+1
			make_branch to_number_continue ; n *token R: token+1

		dq pop_cell ; n *token token+1
		dq two_drop ; n
		dq return
		to_number_continue:
			dq copy ; n *token *token R: token+1
			dq is_digit ; n *token is_digit(*token) R: token+1
			dq stack_not ; n *token !is_digit(*token) R: token+1
			make_branch to_number_error ; n *token R: token+1

		dq literal ; n *token '0' R: token+1
		dq "0"
		dq swap ; n '0' *token R: token+1
		dq stack_sub ; n *token-'0' R: token+1
		dq swap ; *token-'0' n R: token+1
		dq literal ; *token-'0' n 10 R: token+1
		dq 10
		dq stack_mul ; *token-'0' n*10 R: token+1
		dq stack_add ; n R: token+1
		dq pop_cell ; n token+1
		dq swap ; token+1 n
		make_jump to_number_loop
		to_number_error:
			dq two_drop ; R: token+1
			dq pop_cell
			dq drop
			dq true
			dq return

	; ( ch -- )
	make_thread purge_until
		purge_until_loop:
			dq copy
			dq key
			dq equals
			make_branch purge_until_done

		make_jump purge_until_loop
		purge_until_done:
			dq drop
			dq return

	make_header "\", true
	make_thread purge_line
		dq literal
		dq 10
		dq purge_until
		dq return

	make_header "(", true
	make_thread comment
		dq literal
		dq 41
		dq purge_until
		dq return

	; ( name -- token ) Queries the dictionary for the word with the name `name`, returning its token
	make_header "find-word"
	make_thread look_up
		dq dictionary
		dq peek
		look_up_next:
			dq copy ; ( name dict -- name dict dict )
			make_branch look_up_continue ; ( name dict dict -- name dict )

		dq two_drop ; ( name dict -- )
		dq zero ; ( -- zero )
		dq return ; ( zero -- zero )

		look_up_continue:
			dq two_copy ; ( name dict -- name dict name dict )
			dq get_dict_name ; ( name dict name dict -- name dict name &dict->name )
			dq string_equals ; ( name dict name &dict->name -- name dict name===&dict->name )
			make_branch look_up_found ; ( name dict name===&dict.name -- name dict )

		dq get_dict_link ; ( name dict -- name dict->link )
		make_jump look_up_next
		look_up_found:
			dq nip ; ( name dict -- dict )
			dq return

	make_header "dict->len"
	make_thread get_dict_len
		dq peek_byte
		dq literal
		dq 0x80
		dq stack_not
		dq stack_and
		dq return

	make_thread get_dict_immediate
		dq peek_byte
		dq literal
		dq 0x80
		dq stack_and
		dq is_zero
		dq stack_not
		dq return

	; ( dict -- dict->link )
	make_thread get_dict_link
		dq copy
		dq get_dict_len
		dq stack_add
		dq peek
		dq return

	; ( dict -- &dict->name )
	make_thread get_dict_name
		dq increment
		dq return

	; ( dict -- &dict->word )
	make_header "dict->token"
	make_thread get_dict_token
		dq copy
		dq get_dict_len
		dq cell_size
		dq stack_add
		dq stack_add
		dq return

	; ( -- )
	make_thread greet
		dq greeting
		dq print
		dq return

	; ( head -- ) Prints the name of the dictionary entry at `head`
	make_thread print_name
		dq cell_size
		dq stack_add
		dq println
		dq return

	; ( -- 8 ) Implementation cell size
	make_constant cell_size
		dq 8

	; ( a b -- a===b ) String comparison of null-terminated strings; surprisingly difficult
	make_thread string_equals
		string_equals_loop:
			dq copy ; ( a b -- a b b )
			dq peek_byte ; ( a b b -- a b *b )
			dq push_cell ; ( a b *b -- a b )
			dq swap ; ( a b -- b a )
			dq copy ; ( b a -- b a a )
			dq peek_byte ; ( b a a -- b a *a )
			dq pop_cell ; ( b a *a -- b a *a *b )
			dq two_copy ; ( b a *a *b -- b a *a *b *a *b )
			dq is_zero ; (  b a *a *b *a *b --  b a *a *b *a *b==0 )
			dq swap ; ( b a *a *b *a *b==0 -- b a *a *b *b==0 *a )
			dq is_zero ; ( b a *a *b *b==0 *a -- b a *a *b *b==0 *a==0 )
			dq stack_or ; ( b a *a *b *b==0 *a==0 -- b a *a *b !*a||!*b )
			make_branch string_equals_done ; ( b a *a *b !*a||!*b -- b a *a *b )

		dq equals ; ( b a *a *b -- b a *a==*b )
		make_branch string_equals_continue ; ( b a *a==*b -- b a )
		dq two_drop ; ( b a -- )
		dq zero ; ( -- false )
		dq return ; ( false -- false )
		string_equals_continue:
			dq increment ; ( b a -- b a+1 )
			dq swap ; ( b a+1 -- a+1 b )
			dq increment ; ( a+1 b -- a+1 b+1)
			make_jump string_equals_loop

		string_equals_done:
			dq is_zero ; ( b a *a *b -- b a *a !*b )
			dq swap ; ( b a *a !*b -- b a !*b *a )
			dq is_zero ; ( b a !*b *a -- b a !*b !*a )
			dq stack_and ; ( b a !*b !*a -- b a !*a&&!*b )
			dq nip
			dq nip
			dq return ; ( !*a&&!*b -- !*a&&!*b )

	make_variable list_words_msg
		db `Silicon's internal word list contains:\n\n\0`

	make_header "list-words"
	make_thread list_words
		dq list_words_msg
		dq print
		dq dictionary
		dq peek
		make_jump list_words_no_comma
		list_words_loop:
			dq literal
			dq ","
			dq put
			dq literal
			dq `\n`
			dq put

		list_words_no_comma:
			dq copy
			dq increment
			dq print
			dq get_dict_link
			dq copy
			make_branch list_words_loop

		dq newline
		dq newline
		dq drop
		dq return

	make_header "print-number"
	make_thread print_number
		dq copy ; n n
		dq biggest_pow10 ; n p10
		print_number_loop:
			dq swap ; p10 n
			dq two_copy ; p10 n p10 n
			dq stack_div ; p10 n n/p10
			dq literal ; p10 n n/p10 '0'
			dq '0'
			dq stack_add ; p10 n n/p10+'0'
			dq put ; p10 n
			dq two_copy ; p10 n p10 n
			dq modulus ; p10 n n%p10
			dq nip ; p10 n%10
			dq swap ; n%10 p10
			dq literal ; n%10 p10 10
			dq 10
			dq swap ; n%10 10 p10
			dq stack_div ; n%10 p10/10
			dq copy ; n%10 p10/10 p10/10
			make_branch print_number_loop
			dq two_drop
			dq return

	make_thread biggest_pow10
		dq copy
		make_branch biggest_pow10_non_zero
		dq increment
		dq return
		biggest_pow10_non_zero:
			dq literal ; n 1
			dq 1

		biggest_pow10_loop:
			dq two_copy ; n p n p
			dq swap ; n p p n
			dq stack_div ; n p n/p
			dq literal
			dq 10
			dq greater_than ; n p 10>n/p
			make_branch biggest_pow10_done ; n p

		dq literal ; n p 10
		dq 10
		dq stack_mul ; n p*10
		make_jump biggest_pow10_loop
		biggest_pow10_done:
			dq nip ; p
			dq return

	make_variable benchmark_message0
		db `Benchmark averaged \0`

	make_variable benchmark_message1
		db ` cycles/iteration\n\0`

	make_constant benchmark_iterations
		dq 1 << 16

	make_header "benchmark"
	make_thread benchmark
		dq zero
		dq push_cell
		dq benchmark_iterations
		benchmark_loop:
			dq do_rdtsc
			dq do_nothing
			dq do_rdtscp
			dq stack_sub
			dq pop_cell
			dq stack_add
			dq push_cell
			dq literal
			dq 1
			dq swap
			dq stack_sub
			dq copy
			make_branch benchmark_loop

		dq drop
		dq benchmark_iterations
		dq pop_cell
		dq stack_div
		dq benchmark_message0
		dq print
		dq print_number
		dq benchmark_message1
		dq print
		dq newline
		dq return

	make_thread do_nothing
		dq literal
		dq 1024
		do_nothing_loop:
			dq benchmark_message0
			dq benchmark_message1
			dq string_equals
			dq drop
			dq literal
			dq 1
			dq swap
			dq stack_sub
			dq copy
			make_branch do_nothing_loop

		dq drop
		dq return

	make_thread enter_compiler
		dq literal
		dq call_thread
		dq compile_cell
		dq true
		dq compiling
		dq poke
		dq return

	make_thread exit_compiler
		dq zero
		dq compiling
		dq poke
		dq return

	make_thread align_cell
		dq copy ; n n
		dq cell_size ; n n 8
		dq swap ; n 8 n
		dq modulus ; n n%8
		dq cell_size
		dq stack_sub
		dq cell_size
		dq swap
		dq modulus
		dq stack_add
		dq return

	make_header "string-length"
	make_thread string_length
		dq copy
		string_length_loop:
			dq copy
			dq peek_byte
			dq is_zero
			make_branch string_length_done

		dq increment
		make_jump string_length_loop
		string_length_done:
			dq stack_sub
			dq return

	; ( src dst -- )
	make_thread string_copy
		dq push_cell ; src R: dst
		string_copy_loop:
			dq copy ; src src R: dst
			dq peek_byte ; src *src R: dst
			dq copy ; src *src *src R: dst
			dq pop_cell ; src *src *src dst
			dq copy ; src *src *src dst dst
			dq increment ; src *src *src dst dst+1
			dq push_cell ; src *src *src dst R: dst+1
			dq poke_byte ; src *src R: dst+1
			dq is_zero ; src !*src R: dst+1
			make_branch string_copy_done ; src R: dst+1

		dq increment ; src+1 R: dst+1
		make_jump string_copy_loop
		string_copy_done:
			dq pop_cell ; src dst+1
			dq two_drop ;
			dq return

	make_header "create"
	make_thread create_word
		dq get_repl_token ; tok
		dq copy ; tok tok
		dq string_length ; tok len(tok)
		dq increment ; tok len(tok)+1
		dq increment
		dq align_cell ; tok align(len(tok)+1)
		dq free_ptr ; tok align(len(tok)+1) &free
		dq peek ; tok align(len(tok)+1) free
		dq copy ; tok align(len(tok)+1) free free
		dq push_cell ; tok align(len(tok)+1) free R: free
		dq poke_byte ; tok R: free
		dq pop_cell ; tok free
		dq copy ; tok free free
		dq push_cell ; tok free R: free
		dq increment ; tok free+1 R: free
		dq string_copy ; R: free
		dq pop_cell ; free
		dq copy ; free free
		dq copy ; free free free
		dq get_dict_len	; free free free->len
		dq stack_add ; free &free->link
		dq dictionary ; free &free->link &dict
		dq peek ; free &free->link dict
		dq swap ; free dict &free->link
		dq poke ; free
		dq copy ; free free
		dq dictionary ; free free &dict
		dq poke ; free
		dq get_dict_token ; &free->word
		dq free_ptr ; &free->word &free
		dq poke
		dq return

	make_header ":"
	make_thread define
		dq create_word
		dq enter_compiler
		dq return

	make_header ";", true ; yes, highlighting is broken here
	make_thread finish
		dq literal
		dq return
		dq compile_cell
		dq exit_compiler
		dq return

	make_thread stdout
		dq literal
		dq stdout_data
		dq return

	make_thread stdin
		dq literal
		dq stdin_data
		dq return

	make_thread line_buffer
		dq literal
		dq line_buffer_data
		dq return

	make_thread line_ptr
		dq literal
		dq line_ptr_data
		dq return

	make_thread is_fresh_line
		dq literal
		dq is_fresh_line_data
		dq return

	make_thread token_buffer
		dq literal
		dq token_buffer_data
		dq return

	make_thread token_ptr
		dq literal
		dq token_ptr_data
		dq return

	make_thread repl_token_buffer
		dq literal
		dq repl_token_buffer_data
		dq return

	make_thread compiling
		dq literal
		dq compiling_data
		dq return

	make_thread free_ptr
		dq literal
		dq free_ptr_data
		dq return

	make_header "constant"
	make_thread constant
		dq create_word
		dq literal
		dq call_constant
		dq compile_cell
		dq compile_cell
		dq return

section .bss
		resq 512
	data_stack:

		resq 512
	return_stack:

	stdout_data:
		resq 1

	stdin_data:
		resq 1

	; Holds lines of input as they are received
	line_buffer_data:
		resb line_buffer_size

	; Contains the next position to read from in the line buffer
	line_ptr_data:
		resq 1

	; Indicates if the line buffer has just been filled, but not yet touched
	is_fresh_line_data:
		resq 1

	; Memory to hold token strings
	token_buffer_data:
		resb token_max_len

	; Index into token_buffer
	token_ptr_data:
		resq 1

	repl_token_buffer_data:
		resb token_max_len

	compiling_data:
		resq 1

	free_ptr_data:
		resq 1

section .data
	; Contains the actual line read length
	make_variable filled
		dq 1

	; This has to be the last declaration
	make_variable dictionary
		dq header_ %+ latest_header
