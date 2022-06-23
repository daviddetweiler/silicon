public start

extern ExitProcess: proc
extern GetStdHandle: proc
extern WriteFile: proc
extern ReadFile: proc

latest_header = 0

make_header macro id
	local header, name, padding
	header:
		dq latest_header

	name:
		db id, 0

	padding:
		repeat (8 - ((padding - name) mod 8)) mod 8
			db 0
		endm

	latest_header = header
endm

make_word macro name, code
	align 8
	name:
		dq code
endm

make_code_word macro name
	make_word name, name + 8
endm

make_thread macro name
	make_word name, call_thread
endm

make_variable macro name
	make_word name, call_variable
endm

make_constant macro name
	make_word name, call_constant
endm

make_branch macro name
	local next
	dq branch
	dq (name - next) / 8
	next:
endm

make_jump macro name
	local next
	dq jump
	dq (name - next) / 8
	next:
endm

primitives segment alias(".primitives") 'CODE'
	start proc
		sub rsp, 88h ; Stack alignment + 16 parameters
		mov r12, thread
		mov r14, rstack
		mov r15, dstack
		jmp continue
	start endp

	; Begin inner interpreter components

	; Procedure implementing threaded words
	call_thread:
		sub r14, 8
		mov [r14], r12
		mov r12, r13
		jmp continue

	; ( -- ) Returns control from a thread
	make_code_word return
		mov r12, [r14]
		add r14, 8

	; Runs the word referenced at the current IP, advances IP
	continue:
		add r12, 8
		mov r13, [r12 - 8]

	; Runs a word, setting WA to point to the data field
	run:
		add r13, 8
		jmp qword ptr [r13 - 8]

	; ( word-address -- ) Executes the word at `word-address`
	make_header "EXECUTE"
	make_code_word execute
		mov r13, [r15]
		add r15, 8
		jmp run

	; End inner interpreter components

	; Pushes the address of the word data field
	call_variable:
		sub r15, 8
		mov [r15], r13
		jmp continue

	; Pushes the first cell of the word data field
	call_constant:
		mov rcx, [r13]
		sub r15, 8
		mov [r15], rcx
		jmp continue

	; ( -- ) Exits the host process
	make_code_word exit
		xor rcx, rcx
		call ExitProcess

	; ( -- value ) Where `value` is the value of the cell immediately following `literal` in the instruction stream.
	; `literal` resumes execution at the cell following it.
	make_code_word literal
		mov rcx, [r12]
		add r12, 8
		sub r15, 8
		mov [r15], rcx
		jmp continue

	; ( id -- handle ) Retrieves the handle specified by `id`; see the Windows API documentation
	make_code_word get_std_handle
		mov rcx, [r15]
		call GetStdHandle
		mov [r15], rax
		jmp continue

	; ( address -- *address )
	make_header "@"
	make_code_word peek
		mov rcx, [r15]
		mov rcx, [rcx]
		mov [r15], rcx
		jmp continue

	; ( value address -- ) `*address = value`
	make_header "!"
	make_code_word poke
		mov rcx, [r15]
		mov rdx, [r15 + 8]
		mov [rcx], rdx
		add r15, 16
		jmp continue

	; ( byte handle -- ) Writes the first byte of `byte` to `handle`
	make_code_word write_byte
		mov rcx, [r15]
		lea rdx, [r15 + 8]
		mov r8, 1
		mov r9, r15
		mov qword ptr [rsp + 8 * 4], 0
		call WriteFile
		add r15, 16
		jmp continue

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
		jmp continue

	; ( -- ) Similar to `branch`, but does not take a flag, and always jumps
	make_code_word jump
		mov rcx, [r12]
		add r12, 8
		imul rcx, 8
		add r12, rcx
		jmp continue

	; ( buffer handle -- filled ) Read 128 bytes from `handle` into `buffer`; `filled` is the number of bytes actually
	; read
	make_code_word read_line
		mov rcx, [r15]
		mov rdx, [r15 + 8]
		mov r8, 128
		mov r9, r15
		mov qword ptr [rsp + 8 * 4], 0
		call ReadFile
		mov rcx, [r15]
		mov [r15 + 8], rcx
		add r15, 8
		jmp continue

	; ( address -- byte ) Similar to `peek`, but only reads one byte, instead of a full cell
	make_code_word peek_byte
		mov rcx, [r15]
		movzx rcx, byte ptr [rcx]
		mov [r15], rcx
		jmp continue

	; ( byte address -- ) Similar to `poke`, but only writes the first byte of `byte`
	make_code_word poke_byte
		mov rcx, [r15]
		movzx rdx, byte ptr [r15 + 8]
		mov [rcx], rdx
		add r15, 16
		jmp continue

	; ( b a -- mod ) mod = a % b
	make_header "MOD"
	make_code_word modulus
		xor rdx, rdx
		mov rax, [r15]
		div qword ptr [r15 + 8]
		add r15, 8
		mov [r15], edx
		jmp continue

	; ( a -- a a )
	make_header "DUP"
	make_code_word copy
		mov rcx, [r15]
		sub r15, 8
		mov [r15], rcx
		jmp continue

	; ( b a -- a b )
	make_header "SWAP"
	make_code_word swap
		mov rcx, [r15]
		xchg [r15 + 8], rcx
		mov [r15], rcx
		jmp continue

	; ( b a -- c ) c = a + b
	make_header "+"
	make_code_word stack_add
		mov rcx, [r15]
		add r15, 8
		add [r15], rcx
		jmp continue

	; ( a -- )
	make_header "DROP"
	make_code_word drop
		add r15, 8
		jmp continue

	; ( a b -- c ) c = a == b
	make_header "="
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
		jmp continue

	; ( a b -- c ) c = a | b
	make_header "OR"
	make_code_word stack_or
		mov rcx, [r15]
		add r15, 8
		or [r15], rcx
		jmp continue

	; ( a -- ~a )
	make_header "NOT"
	make_code_word stack_not
		mov rcx, [r15]
		not rcx
		mov [r15], rcx
		jmp continue

	; ( a -- b ) b = a + 1
	make_header "+1"
	make_code_word increment
		add qword ptr [r15], 1
		jmp continue
primitives ends

constants segment readonly alias(".rdata") 'CONST'
	; The initial thread executed by `start`
	thread:
		dq init_io
		dq greeting
		dq print
		dq literal
		dq dictionary
		dq walk
		dq echo_tokens
		dq exit

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
	make_header "EMIT"
	make_thread emit
		dq stdout
		dq peek
		dq write_byte
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
	make_header "KEY"
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

	; ( -- 0 )
	make_header "FALSE"
	make_constant zero
		dq 0

	; ( -- ) Runs in a loop, accepting input from `stdin`, and writing out tokens, one on each line. Returns at EOF.
	make_thread echo_tokens
		echo_tokens_next:
			dq get_token
			dq copy
			make_branch echo_tokens_echo
		dq drop
		dq return
		echo_tokens_echo:
			dq println
			make_jump echo_tokens_next

	; ( string -- ) Prints `string` with a terminal newline.
	make_thread println
		dq print
		dq literal
		dq 10
		dq emit
		dq return

	; ( -- token ) `token` points to the next null-terminated token.
	make_thread get_token
		dq skip_space
		dq zero
		dq token_ptr
		dq poke
		get_token_loop:
			dq key ; ( ch -- )
			dq copy ; ( ch ch -- )
			make_branch get_token_ok
			dq drop ; ( -- )
			dq zero
			dq return
		get_token_ok:
			dq copy ; ( ch ch -- )
			dq token_buffer ; ( ch ch &tb -- )
			dq token_ptr ; ( * &tp -- )
			dq copy ; ( * &tp &tp -- )
			dq peek ; ( * &tp tp -- )
			dq swap ; ( * tp &tp -- )
			dq copy ; ( * tp &tp &tp -- )
			dq peek ; ( * tp &tp tp -- )
			dq increment ; ( * tp &tp tp + 1 -- )
			dq swap ; ( * tp tp + 1 &tp -- )
			dq poke ; ( * &tb tp -- )
			dq stack_add ; ( ch ch &tb[tp] -- )
			dq poke_byte ; ( ch -- )
			dq is_space ; ( sp -- )
			dq stack_not ; ( !sp -- )
			make_branch get_token_loop
		dq token_buffer
		dq copy
		dq token_ptr
		dq peek
		dq literal
		dq -1
		dq stack_add
		dq stack_add
		dq zero
		dq swap
		dq poke_byte
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
		dq 9
		dq equals
		dq swap
		dq copy
		dq literal
		dq 13
		dq equals
		dq swap
		dq literal
		dq 10
		dq equals
		dq stack_or
		dq stack_or
		dq stack_or
		dq return

	; ( string -- ) Write `string` to `stdin`.
	make_header "TYPE"
	make_thread print
		print_next:
			dq copy ; ( str -- str str )
			dq peek_byte ; ( str str -- str ch )
			dq copy ; ( str ch -- str ch ch )
			make_branch print_continue
		dq drop ; ( str ch -- str )
		dq drop ; ( str -- )
		dq return
		print_continue:
			dq emit ; ( str ch -- str )
			dq increment ; ( str -- str + 1 )
			make_jump print_next

	; This is the banner
	make_variable greeting
		db "SILICON (C) 2022 DAVID DETWEILER", 10, 10, 0

	; The ANSI Forth standard value for `TRUE`
	make_header "TRUE"
	make_constant true
		dq 0ffffffffffffffffh

	; ( head -- ) Walks a dictionary list at `head`, printing each word to its own line
	make_thread walk
		walk_next:
			dq copy ; ( head -- head head )
			make_branch walk_continue
		dq drop ; ( head -- )
		dq return ; ( -- )
		walk_continue:
			dq copy ; ( head -- head head )
			dq print_name ; ( head head -- head )
			dq peek ; ( head -- head.next )
			make_jump walk_next

	; ( head -- ) Prints the name of the dictionary entry at `head`
	make_thread print_name
		dq cell_size
		dq stack_add
		dq println
		dq return

	; ( -- 8 ) Implementation cell size
	make_constant cell_size
		dq 8
constants ends

data segment alias(".data") 'DATA'
		repeat 64
			dq 0
		endm
	dstack:

		repeat 64
			dq 0
		endm
	rstack:

	make_variable stdout
		dq 0
	
	make_variable stdin
		dq 0

	; Holds lines of input as they are received
	make_variable line_buffer
		repeat 128
			db 0
		endm

	; Contains the next position to read from in the line buffer
	make_variable line_ptr
		dq 0

	; Contains the actual line read length
	make_variable filled
		dq 1

	; Indicates if the line buffer has just been filled, but not yet touched
	make_variable is_fresh_line
		dq 0

	; Memory to hold token strings
	make_variable token_buffer
		repeat 64
			db 0
		endm

	; Index into token_buffer
	make_variable token_ptr
		dq 0
data ends

dictionary = latest_header

end
