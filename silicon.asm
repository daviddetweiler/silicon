PUBLIC START

EXTERN ExitProcess: PROC
EXTERN GetStdHandle: PROC
EXTERN WriteFile: PROC
EXTERN ReadFile: PROC

SILICON SEGMENT READ WRITE EXECUTE ALIAS("SILICON")
START PROC
    SUB RSP, 88H ; Stack alignment + 16 parameters
    MOV R12, THREAD
    MOV R14, RSTACK
    MOV R15, DSTACK
    JMP CONTINUE
    ALIGN 8
START ENDP

REPEAT 64
    DQ 0
ENDM
DSTACK:

REPEAT 64
    DQ 0
ENDM
RSTACK:

; Begin inner interpreter components

; Procedure implementing threaded words
DOTHREAD:
    SUB R14, 8
    MOV [R14], R12
    MOV R12, R13
    JMP CONTINUE
    ALIGN 8

; Procedure implementing thread returns
RETURN:
    DQ RETURN+8
    MOV R12, [R14]
    ADD R14, 8

; Runs the word referenced at the current IP, advances IP
CONTINUE:
    ADD R12, 8
    MOV R13, [R12-8]

; Runs a word, setting WA to point to the data field
RUN:
    ADD R13, 8
    JMP QWORD PTR [R13-8]
    ALIGN 8

EXECUTEHEADER:
    DB 7 ; Name length
    DB "EXECUTE"
    ALIGN 8
    DQ 0 ; Link field

; Pops a word address from the data stack and executes it
EXECUTE:
    DQ EXECUTE+8
    MOV R13, [R15]
    ADD R15, 8
    JMP RUN
    ALIGN 8

; End inner interpreter components

EXIT:
    DQ EXIT+8
    XOR RCX, RCX
    CALL ExitProcess
    ALIGN 8

THREAD:
    DQ INITIO
    DQ ECHOTEXT
    DQ EXIT

LITERAL:
    DQ LITERAL+8
    MOV RCX, [R12]
    ADD R12, 8
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

INITIO:
    DQ DOTHREAD
    DQ LITERAL
    DQ -11
    DQ GETSTD
    DQ STDOUT
    DQ POKE
    DQ LITERAL
    DQ -10
    DQ GETSTD
    DQ STDIN
    DQ POKE
    DQ RETURN

PUT:
    DQ DOTHREAD
    DQ STDOUT
    DQ PEEK
    DQ PUTBYTE
    DQ RETURN

GETSTD:
    DQ GETSTD+8
    MOV RCX, [R15]
    CALL GetStdHandle
    MOV [R15], RAX
    JMP CONTINUE
    ALIGN 8

PEEK:
    DQ PEEK+8
    MOV RCX, [R15]
    MOV RCX, [RCX]
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

POKE:
    DQ POKE+8
    MOV RCX, [R15]
    MOV RDX, [R15+8]
    MOV [RCX], RDX
    ADD R15, 16
    JMP CONTINUE
    ALIGN 8

PUTBYTE:
    DQ PUTBYTE+8
    MOV RCX, [R15]
    LEA RDX, [R15+8]
    MOV R8, 1
    MOV R9, R15
    MOV QWORD PTR [RSP+8*4], 0
    CALL WriteFile
    ADD R15, 16
    JMP CONTINUE
    ALIGN 8

DOVARIABLE:
    SUB R15, 8
    MOV [R15], R13
    JMP CONTINUE
    ALIGN 8

STDOUT:
    DQ DOVARIABLE
    DQ 0

STDIN:
    DQ DOVARIABLE
    DQ 0

LINEBUFFER:
    DQ DOVARIABLE
REPEAT 128
    DB 0
ENDM

; ( flag -- )
;
; Expects a literal signed branch constant; if `flag` is zero, resumes execution after the constant, else it adjusts the
; IP by the branch offset in units of cells.
BRANCH:
    DQ BRANCH+8
    MOV RCX, [R12]
    ADD R12, 8
    MOV RDX, [R15]
    ADD R15, 8
    TEST RDX, RDX
    SETNE DL
    IMUL RCX, RDX
    IMUL RCX, 8
    ADD R12, RCX
    JMP CONTINUE
    ALIGN 8

; ( buffer handle -- filled )
;
; Read 128 bytes from `handle` into `buffer`; `filled` is the number of bytes actually read
READLINE:
    DQ READLINE+8
    MOV RCX, [R15]
    MOV RDX, [R15+8]
    MOV R8, 128
    MOV R9, R15
    MOV QWORD PTR [RSP+8*4], 0
    CALL ReadFile
    MOV RCX, [R15]
    MOV [R15+8], RCX
    ADD R15, 8
    JMP CONTINUE
    ALIGN 8

REFILL:
    DQ DOTHREAD
    DQ LINEBUFFER
    DQ STDIN
    DQ PEEK
    DQ READLINE
    DQ FILLED
    DQ POKE
    DQ RETURN

PEEKBYTE:
    DQ PEEKBYTE+8
    MOV RCX, [R15]
    MOVZX RCX, BYTE PTR [RCX]
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

GET:
    DQ DOTHREAD
    DQ IOPOINTER
    DQ PEEK
    DQ FILLED
    DQ PEEK
    DQ SWAP
    DQ MODULUS
    DQ BRANCH
    DQ 12
    DQ REFILL
    DQ FILLED
    DQ PEEK
    DQ BRANCH
    DQ 3
    DQ LITERAL
    DQ 0
    DQ RETURN
    DQ LITERAL
    DQ 0
    DQ IOPOINTER
    DQ POKE
    DQ GETIOBYTE
    DQ RETURN

; Unsafe; does not range-check line buffer
GETIOBYTE:
    DQ DOTHREAD
    DQ IOPOINTER
    DQ PEEK
    DQ COPY
    DQ LITERAL
    DQ 1
    DQ SUM
    DQ IOPOINTER
    DQ POKE
    DQ LINEBUFFER
    DQ SUM
    DQ PEEKBYTE
    DQ RETURN

; ( b a -- mod )
;
; mod = a % b
MODULUS:
    DQ MODULUS+8
    XOR RDX, RDX
    MOV RAX, [R15]
    DIV QWORD PTR [R15+8]
    ADD R15, 8
    MOV [R15], EDX
    JMP CONTINUE
    ALIGN 8

COPY:
    DQ COPY+8
    MOV RCX, [R15]
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

SWAP:
    DQ SWAP+8
    MOV RCX, [R15]
    XCHG [R15+8], RCX
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

SUM:
    DQ SUM+8
    MOV RCX, [R15]
    ADD R15, 8
    ADD [R15], RCX
    JMP CONTINUE
    ALIGN 8

IOPOINTER:
    DQ DOVARIABLE
    DQ 0

FILLED:
    DQ DOVARIABLE
    DQ 1

ECHOTEXT:
    DQ DOTHREAD
    DQ GET
    DQ COPY
    DQ BRANCH
    DQ 1
    DQ RETURN
    DQ PUT
    DQ LITERAL
    DQ 1
    DQ BRANCH
    DQ -10
    DQ RETURN

SILICON ENDS

END
