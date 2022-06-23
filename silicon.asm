PUBLIC START

EXTERN ExitProcess: PROC
EXTERN GetStdHandle: PROC
EXTERN WriteFile: PROC
EXTERN ReadFile: PROC

NULLHEADER EQU 0

HEADER MACRO NAME, ID, PREVIOUS
    ALIGN 8

&NAME&HEADER:
    DB &NAME&LINK - &NAME&LINK

&NAME&NAME:
    DB ID

&NAME&LINK:
    ALIGN 8
    DQ &PREVIOUS&HEADER

ENDM

NEWCODE MACRO NAME
    ALIGN 8

NAME:
    DQ NAME+8
ENDM

NEWWORD MACRO NAME, CODE
    ALIGN 8

NAME:
    DQ CODE

ENDM

SILICON SEGMENT READ WRITE EXECUTE ALIAS("SILICON")
START PROC
    SUB RSP, 88H ; Stack alignment + 16 parameters
    MOV R12, THREAD
    MOV R14, RSTACK
    MOV R15, DSTACK
    JMP CONTINUE
START ENDP

    ALIGN 8

REPEAT 64
    DQ 0
ENDM
DSTACK:

REPEAT 64
    DQ 0
ENDM
RSTACK:

THREAD:
    DQ INITIO
    DQ GREETING
    DQ PRINT
    DQ ECHOTOKENS
    DQ EXIT

; Begin inner interpreter components

; Procedure implementing threaded words
DOTHREAD:
    SUB R14, 8
    MOV [R14], R12
    MOV R12, R13
    JMP CONTINUE

; Procedure implementing thread returns
NEWCODE RETURN
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

; Pops a word address from the data stack and executes it
HEADER EXECUTE, "EXECUTE", NULL
NEWCODE EXECUTE
    MOV R13, [R15]
    ADD R15, 8
    JMP RUN

; End inner interpreter components

NEWCODE EXIT
    XOR RCX, RCX
    CALL ExitProcess

NEWCODE LITERAL
    MOV RCX, [R12]
    ADD R12, 8
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE

NEWWORD INITIO, DOTHREAD
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

NEWWORD PUT, DOTHREAD
    DQ STDOUT
    DQ PEEK
    DQ PUTBYTE
    DQ RETURN

NEWCODE GETSTD
    MOV RCX, [R15]
    CALL GetStdHandle
    MOV [R15], RAX
    JMP CONTINUE

; ( a -- v )
; v = *a
NEWCODE PEEK
    MOV RCX, [R15]
    MOV RCX, [RCX]
    MOV [R15], RCX
    JMP CONTINUE

; ( v a -- )
;
; *a = v
NEWCODE POKE
    MOV RCX, [R15]
    MOV RDX, [R15+8]
    MOV [RCX], RDX
    ADD R15, 16
    JMP CONTINUE

NEWCODE PUTBYTE
    MOV RCX, [R15]
    LEA RDX, [R15+8]
    MOV R8, 1
    MOV R9, R15
    MOV QWORD PTR [RSP+8*4], 0
    CALL WriteFile
    ADD R15, 16
    JMP CONTINUE

DOVARIABLE:
    SUB R15, 8
    MOV [R15], R13
    JMP CONTINUE

NEWWORD STDOUT, DOVARIABLE
    DQ 0

NEWWORD STDIN, DOVARIABLE
    DQ 0

NEWWORD LINEBUFFER, DOVARIABLE
REPEAT 128
    DB 0
ENDM

; ( flag -- )
;
; Expects a literal signed branch constant; if `flag` is zero, resumes execution after the constant, else it adjusts the
; IP by the branch offset in units of cells.
NEWCODE BRANCH
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

NEWCODE JUMP
    MOV RCX, [R12]
    ADD R12, 8
    IMUL RCX, 8
    ADD R12, RCX
    JMP CONTINUE

; ( buffer handle -- filled )
;
; Read 128 bytes from `handle` into `buffer`; `filled` is the number of bytes actually read
NEWCODE READLINE
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

; ( -- !iseof )
NEWWORD REFILL, DOTHREAD
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

NEWCODE PEEKBYTE
    MOV RCX, [R15]
    MOVZX RCX, BYTE PTR [RCX]
    MOV [R15], RCX
    JMP CONTINUE

; ( -- ch )
;
; ch is either the next character from stdin, or null on EOF
NEWWORD GET, DOTHREAD
    DQ PEEKCHAR ; ( lb[iop] -- )
    DQ NEXTCHAR
    DQ RETURN

NEWWORD IOPOINTER, DOVARIABLE
    DQ 0

NEWWORD FILLED, DOVARIABLE
    DQ 1

NEWWORD PEEKCHAR, DOTHREAD
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

NEWWORD NEXTCHAR, DOTHREAD
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

NEWWORD ISFRESHLINE, DOVARIABLE
    DQ 0

; ( -- !iseof )
NEWWORD FILLIFEMPTY, DOTHREAD
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

NEWWORD INCREMENT, DOTHREAD
    DQ LITERAL
    DQ 1
    DQ SUM
    DQ RETURN

NEWWORD ZERO, DOCONSTANT
    DQ 0

DOCONSTANT:
    MOV RCX, [R13]
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE

; ( b a -- mod )
;
; mod = a % b
NEWCODE MODULUS
    XOR RDX, RDX
    MOV RAX, [R15]
    DIV QWORD PTR [R15+8]
    ADD R15, 8
    MOV [R15], EDX
    JMP CONTINUE

; ( a -- a a )
NEWCODE COPY
    MOV RCX, [R15]
    SUB R15, 8
    MOV [R15], RCX
    JMP CONTINUE

; ( b a -- a b )
NEWCODE SWAP
    MOV RCX, [R15]
    XCHG [R15+8], RCX
    MOV [R15], RCX
    JMP CONTINUE

; ( b a -- c )
;
; c = a + b
NEWCODE SUM
    MOV RCX, [R15]
    ADD R15, 8
    ADD [R15], RCX
    JMP CONTINUE

NEWWORD ECHOTOKENS, DOTHREAD
    DQ GETTOKEN
    DQ COPY
    DQ BRANCH
    DQ 2
    DQ DROP
    DQ RETURN
    DQ PRINTLINE
    DQ JUMP
    DQ -9

NEWWORD PRINTLINE, DOTHREAD
    DQ PRINT
    DQ LITERAL
    DQ 10
    DQ PUT
    DQ RETURN

NEWWORD TOKENBUFFER, DOVARIABLE
REPEAT 64
    DB 0
ENDM

NEWWORD TOKENPOINTER, DOVARIABLE
    DQ 0

; ( -- token )
;
; `token` points to a null-terminated token
NEWWORD GETTOKEN, DOTHREAD
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

NEWWORD SKIPSPACE, DOTHREAD
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
NEWWORD ISSPACE, DOTHREAD
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

NEWCODE EQUALSBYTE
    MOV CL, [R15]
    ADD R15, 8
    CMP CL, [R15]
    SETE CL
    MOVZX RCX, CL
    MOV [R15], RCX
    JMP CONTINUE

NEWCODE BITOR
    MOV RCX, [R15]
    ADD R15, 8
    OR [R15], RCX
    JMP CONTINUE

NEWCODE LOGICNOT
    MOV RCX, [R15]
    TEST RCX, RCX
    SETZ CL
    MOVZX RCX, CL
    MOV [R15], RCX
    JMP CONTINUE

NEWCODE POKEBYTE
    MOV RCX, [R15]
    MOVZX RDX, BYTE PTR [R15+8]
    MOV [RCX], RDX
    ADD R15, 16
    JMP CONTINUE

NEWWORD PRINT, DOTHREAD
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

NEWWORD GREETING, DOVARIABLE
    DB "SILICON (C) 2022 DAVID DETWEILER", 10, 10, 0

NEWCODE DROP
    ADD R15, 8
    JMP CONTINUE

SILICON ENDS

END
