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
    DQ GREETING
    DQ PRINT
    DQ ECHOTOKENS
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

; ( a -- v )
; v = *a
PEEK:
    DQ PEEK+8
    MOV RCX, [R15]
    MOV RCX, [RCX]
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

; ( v a -- )
;
; *a = v
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
    MOVZX RDX, DL
    IMUL RCX, RDX
    IMUL RCX, 8
    ADD R12, RCX
    JMP CONTINUE
    ALIGN 8

JUMP:
    DQ JUMP+8
    MOV RCX, [R12]
    ADD R12, 8
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

; ( -- !iseof )
REFILL:
    DQ DOTHREAD
    DQ LINEBUFFER
    DQ STDIN
    DQ PEEK
    DQ READLINE
    DQ COPY
    DQ FILLED
    DQ POKE
    DQ ZERO
    DQ IOPOINTER
    DQ POKE
    DQ LITERAL
    DQ 1
    DQ ISFRESHLINE
    DQ POKE
    DQ RETURN

PEEKBYTE:
    DQ PEEKBYTE+8
    MOV RCX, [R15]
    MOVZX RCX, BYTE PTR [RCX]
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

; ( -- ch )
;
; ch is either the next character from stdin, or null on EOF
GET:
    DQ DOTHREAD
    DQ PEEKCHAR ; ( lb[iop] -- )
    DQ NEXTCHAR
    DQ RETURN

IOPOINTER:
    DQ DOVARIABLE
    DQ 0

FILLED:
    DQ DOVARIABLE
    DQ 1

PEEKCHAR:
    DQ DOTHREAD
    DQ FILLIFEMPTY ; ( -- !iseof )
    DQ BRANCH
    DQ 2
    DQ ZERO
    DQ RETURN
    DQ IOPOINTER ; ( &iop -- )
    DQ PEEK ; ( iop -- )
    DQ LINEBUFFER ; ( iop &lb -- )
    DQ SUM ; ( &lb[iop] -- )
    DQ PEEKBYTE ; ( lb[iop] -- )
    DQ RETURN

NEXTCHAR:
    DQ DOTHREAD
    DQ ZERO
    DQ ISFRESHLINE
    DQ POKE
    DQ IOPOINTER ; ( &iop -- )
    DQ COPY ; ( &iop &iop -- )
    DQ PEEK ; ( &iop iop -- )
    DQ INCREMENT ; ( &iop iop+1 -- )
    DQ SWAP ; ( iop+1 &iop -- )
    DQ POKE ; ( -- )
    DQ RETURN

ISFRESHLINE:
    DQ DOVARIABLE
    DQ 0

; ( -- !iseof )
FILLIFEMPTY:
    DQ DOTHREAD
    DQ FILLED
    DQ PEEK
    DQ BRANCH
    DQ 3
    DQ LITERAL
    DQ 0
    DQ RETURN
    DQ ISFRESHLINE
    DQ PEEK
    DQ LOGICNOT
    DQ BRANCH
    DQ 3
    DQ LITERAL
    DQ 1
    DQ RETURN
    DQ FILLED ; ( &fill -- )
    DQ PEEK ; ( fill -- )
    DQ IOPOINTER ; ( fill &iop -- )
    DQ PEEK ; ( fill iop -- )
    DQ MODULUS ; ( iop%fill -- )
    DQ BRANCH ; ( -- )
    DQ 2
    DQ REFILL ; ( -- !iseof )
    DQ RETURN
    DQ LITERAL
    DQ 1
    DQ RETURN

INCREMENT:
    DQ DOTHREAD
    DQ LITERAL
    DQ 1
    DQ SUM
    DQ RETURN

ZERO:
    DQ DOCONSTANT
    DQ 0

DOCONSTANT:
    MOV RCX, [R13]
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

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

; ( a -- a a )
COPY:
    DQ COPY+8
    MOV RCX, [R15]
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

; ( b a -- a b )
SWAP:
    DQ SWAP+8
    MOV RCX, [R15]
    XCHG [R15+8], RCX
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

; ( b a -- c )
;
; c = a + b
SUM:
    DQ SUM+8
    MOV RCX, [R15]
    ADD R15, 8
    ADD [R15], RCX
    JMP CONTINUE
    ALIGN 8

ECHOTOKENS:
    DQ DOTHREAD
    DQ GETTOKEN
    DQ COPY
    DQ BRANCH
    DQ 2
    DQ DROP
    DQ RETURN
    DQ PRINTLINE
    DQ JUMP
    DQ -9

PRINTLINE:
    DQ DOTHREAD
    DQ PRINT
    DQ LITERAL
    DQ 13
    DQ PUT
    DQ LITERAL
    DQ 10
    DQ PUT
    DQ RETURN

BREAK:
    DQ BREAK+8
    INT 3
    JMP CONTINUE
    ALIGN 8

TOKENBUFFER:
    DQ DOVARIABLE
REPEAT 64
    DB 0
ENDM

TOKENPOINTER:
    DQ DOVARIABLE
    DQ 0

; ( -- token )
;
; `token` points to a null-terminated token
GETTOKEN:
    DQ DOTHREAD
    DQ SKIPSPACE
    DQ LITERAL
    DQ 0
    DQ TOKENPOINTER
    DQ POKE
    DQ GET ; ( ch -- )
    DQ COPY ; ( ch ch -- )
    DQ BRANCH ; ( ch -- )
    DQ 3
    DQ DROP ; ( -- )
    DQ ZERO
    DQ RETURN
    DQ COPY ; ( ch ch -- )
    DQ TOKENBUFFER ; ( ch ch &tb -- )
    DQ TOKENPOINTER ; ( * &tp -- )
    DQ COPY ; ( * &tp &tp -- )
    DQ PEEK ; ( * &tp tp -- )
    DQ SWAP ; ( * tp &tp -- )
    DQ COPY ; ( * tp &tp &tp -- )
    DQ PEEK ; ( * tp &tp tp -- )
    DQ INCREMENT ; ( * tp &tp tp+1 -- )
    DQ SWAP ; ( * tp tp+1 &tp -- )
    DQ POKE ; ( * &tb tp -- )
    DQ SUM ; ( ch ch &tb[tp] -- )
    DQ POKEBYTE ; ( ch -- )
    DQ ISSPACE ; ( sp -- )
    DQ LOGICNOT ; ( !sp -- )
    DQ BRANCH
    DQ -24
    DQ TOKENBUFFER
    DQ COPY
    DQ TOKENPOINTER
    DQ PEEK
    DQ LITERAL
    DQ -1
    DQ SUM
    DQ SUM
    DQ ZERO
    DQ SWAP
    DQ POKEBYTE
    DQ RETURN

SKIPSPACE:
    DQ DOTHREAD
    DQ PEEKCHAR
    DQ ISSPACE
    DQ BRANCH
    DQ 1
    DQ RETURN
    DQ NEXTCHAR
    DQ JUMP
    DQ -8

; ( ch -- sp )
;
; sp = ch in ['\r', '\n', '\t', ' ']
ISSPACE:
    DQ DOTHREAD
    DQ COPY ; ( ch ch -- )
    DQ LITERAL
    DQ " "
    DQ EQUALSBYTE ; ( ch ch==' ' -- )
    DQ SWAP ; ( ch==' ' ch -- )
    DQ COPY
    DQ LITERAL
    DQ 9
    DQ EQUALSBYTE
    DQ SWAP
    DQ COPY
    DQ LITERAL
    DQ 13
    DQ EQUALSBYTE
    DQ SWAP
    DQ LITERAL
    DQ 10
    DQ EQUALSBYTE
    DQ BITOR
    DQ BITOR
    DQ BITOR
    DQ RETURN

EQUALSBYTE:
    DQ EQUALSBYTE+8
    MOV CL, [R15]
    ADD R15, 8
    CMP CL, [R15]
    SETE CL
    MOVZX RCX, CL
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

BITOR:
    DQ BITOR+8
    MOV RCX, [R15]
    ADD R15, 8
    OR [R15], RCX
    JMP CONTINUE
    ALIGN 8

LOGICNOT:
    DQ LOGICNOT+8
    MOV RCX, [R15]
    TEST RCX, RCX
    SETZ CL
    MOVZX RCX, CL
    MOV [R15], RCX
    JMP CONTINUE
    ALIGN 8

POKEBYTE:
    DQ POKEBYTE+8
    MOV RCX, [R15]
    MOVZX RDX, BYTE PTR [R15+8]
    MOV [RCX], RDX
    ADD R15, 16
    JMP CONTINUE
    ALIGN 8

PRINT:
    DQ DOTHREAD
    DQ COPY
    DQ PEEKBYTE
    DQ COPY
    DQ BRANCH
    DQ 3
    DQ DROP
    DQ DROP
    DQ RETURN
    DQ PUT
    DQ INCREMENT
    DQ JUMP
    DQ -12

GREETING:
    DQ DOVARIABLE
    DB "Hello, world!", 13, 10, 0
    ALIGN 8

DROP:
    DQ DROP+8
    ADD R15, 8
    JMP CONTINUE
    ALIGN 8

SILICON ENDS

END
