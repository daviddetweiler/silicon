PUBLIC START

EXTERN ExitProcess: PROC
EXTERN GetStdHandle: PROC
EXTERN WriteFile: PROC
EXTERN ReadFile: PROC

LATEST = 0

NEWHEADER MACRO ID
    LOCAL HEADER, NAME, PAD

    HEADER:
        DQ LATEST

    NAME:
        DB ID, 0

    PAD:
        REPEAT (8-((PAD-NAME) MOD 8)) MOD 8
            DB 0
        ENDM

    LATEST = HEADER
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

NEWTHREAD MACRO NAME
    NEWWORD NAME, DOTHREAD
ENDM

NEWVARIABLE MACRO NAME
    NEWWORD NAME, DOVARIABLE
ENDM

NEWCONSTANT MACRO NAME
    NEWWORD NAME, DOCONSTANT
ENDM

TEXT SEGMENT ALIAS(".text") 'CODE'
    START PROC
        SUB RSP, 88H ; Stack alignment + 16 parameters
        MOV R12, THREAD
        MOV R14, RSTACK
        MOV R15, DSTACK
        JMP CONTINUE
    START ENDP

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
    NEWHEADER "EXECUTE"
    NEWCODE EXECUTE
        MOV R13, [R15]
        ADD R15, 8
        JMP RUN

    ; End inner interpreter components

    NEWCODE EXIT
        XOR RCX, RCX
        CALL ExitProcess

    NEWCODE BREAK
        INT 3
        JMP CONTINUE

    NEWCODE LITERAL
        MOV RCX, [R12]
        ADD R12, 8
        SUB R15, 8
        MOV [R15], RCX
        JMP CONTINUE

    NEWCODE GETSTD
        MOV RCX, [R15]
        CALL GetStdHandle
        MOV [R15], RAX
        JMP CONTINUE

    ; ( a -- v )
    ; v = *a
    NEWHEADER "@"
    NEWCODE PEEK
        MOV RCX, [R15]
        MOV RCX, [RCX]
        MOV [R15], RCX
        JMP CONTINUE

    ; ( v a -- )
    ;
    ; *a = v
    NEWHEADER "!"
    NEWCODE POKE
        MOV RCX, [R15]
        MOV RDX, [R15+8]
        MOV [RCX], RDX
        ADD R15, 16
        JMP CONTINUE

    NEWCODE WRITEBYTE
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

    NEWCODE PEEKBYTE
        MOV RCX, [R15]
        MOVZX RCX, BYTE PTR [RCX]
        MOV [R15], RCX
        JMP CONTINUE

    DOCONSTANT:
        MOV RCX, [R13]
        SUB R15, 8
        MOV [R15], RCX
        JMP CONTINUE

    ; ( b a -- mod )
    ;
    ; mod = a % b
    NEWHEADER "MOD"
    NEWCODE MODULUS
        XOR RDX, RDX
        MOV RAX, [R15]
        DIV QWORD PTR [R15+8]
        ADD R15, 8
        MOV [R15], EDX
        JMP CONTINUE

    ; ( a -- a a )
    NEWHEADER "DUP"
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
    NEWHEADER "+"
    NEWCODE SUM
        MOV RCX, [R15]
        ADD R15, 8
        ADD [R15], RCX
        JMP CONTINUE

    NEWHEADER "DROP"
    NEWCODE DROP
        ADD R15, 8
        JMP CONTINUE

    NEWHEADER "="
    NEWCODE EQUALS
        MOV RCX, [R15]
        ADD R15, 8
        CMP RCX, [R15]
        SETE CL
        MOVZX RCX, CL
        XOR RDX, RDX
        NOT RDX
        IMUL RCX, RDX
        MOV [R15], RCX
        JMP CONTINUE

    NEWHEADER "OR"
    NEWCODE BITOR
        MOV RCX, [R15]
        ADD R15, 8
        OR [R15], RCX
        JMP CONTINUE

    NEWHEADER "NOT"
    NEWCODE BITNOT
        MOV RCX, [R15]
        NOT RCX
        MOV [R15], RCX
        JMP CONTINUE

    NEWCODE POKEBYTE
        MOV RCX, [R15]
        MOVZX RDX, BYTE PTR [R15+8]
        MOV [RCX], RDX
        ADD R15, 16
        JMP CONTINUE
TEXT ENDS

RDATA SEGMENT READONLY ALIAS(".rdata") 'CONST'
    THREAD:
        DQ INITIO
        DQ GREETING
        DQ PRINT
        DQ LITERAL
        DQ DICTIONARY
        DQ WALK
        DQ EXIT

    NEWTHREAD INITIO
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

    NEWHEADER "EMIT"
    NEWTHREAD EMIT
        DQ STDOUT
        DQ PEEK
        DQ WRITEBYTE
        DQ RETURN

    ; ( -- !iseof )
    NEWTHREAD REFILL
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
        DQ TRUE
        DQ ISFRESHLINE
        DQ POKE
        DQ RETURN

    ; ( -- ch )
    ;
    ; ch is either the next character from stdin, or null on EOF
    NEWHEADER "KEY"
    NEWTHREAD KEY
        DQ PEEKCHAR ; ( lb[iop] -- )
        DQ NEXTCHAR
        DQ RETURN

    NEWTHREAD PEEKCHAR
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

    NEWTHREAD NEXTCHAR
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

    ; ( -- !iseof )
    NEWTHREAD FILLIFEMPTY
        DQ FILLED
        DQ PEEK
        DQ BRANCH
        DQ 3
        DQ LITERAL
        DQ 0
        DQ RETURN
        DQ ISFRESHLINE
        DQ PEEK
        DQ BITNOT
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

    NEWHEADER "+1"
    NEWTHREAD INCREMENT
        DQ LITERAL
        DQ 1
        DQ SUM
        DQ RETURN

    NEWHEADER "FALSE"
    NEWCONSTANT ZERO
        DQ 0

    NEWTHREAD ECHOTOKENS
        DQ GETTOKEN
        DQ COPY
        DQ BRANCH
        DQ 2
        DQ DROP
        DQ RETURN
        DQ PRINTLINE
        DQ JUMP
        DQ -9

    NEWTHREAD PRINTLINE
        DQ PRINT
        DQ LITERAL
        DQ 10
        DQ EMIT
        DQ RETURN

    ; ( -- token )
    ;
    ; `token` points to a null-terminated token
    NEWTHREAD GETTOKEN
        DQ SKIPSPACE
        DQ LITERAL
        DQ 0
        DQ TOKENPOINTER
        DQ POKE
        DQ KEY ; ( ch -- )
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
        DQ BITNOT ; ( !sp -- )
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

    NEWTHREAD SKIPSPACE
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
    NEWTHREAD ISSPACE
        DQ COPY ; ( ch ch -- )
        DQ LITERAL
        DQ " "
        DQ EQUALS ; ( ch ch==' ' -- )
        DQ SWAP ; ( ch==' ' ch -- )
        DQ COPY
        DQ LITERAL
        DQ 9
        DQ EQUALS
        DQ SWAP
        DQ COPY
        DQ LITERAL
        DQ 13
        DQ EQUALS
        DQ SWAP
        DQ LITERAL
        DQ 10
        DQ EQUALS
        DQ BITOR
        DQ BITOR
        DQ BITOR
        DQ RETURN

    NEWHEADER "TYPE"
    NEWTHREAD PRINT
        DQ COPY ; ( str -- str str )
        DQ PEEKBYTE ; ( str str -- str ch )
        DQ COPY ; ( str ch -- str ch ch )
        DQ BRANCH ; ( str ch ch -- str ch )
        DQ 3
        DQ DROP ; ( str ch -- str )
        DQ DROP ; ( str -- )
        DQ RETURN
        DQ EMIT ; ( str ch -- str )
        DQ INCREMENT ; ( str -- str+1 )
        DQ JUMP
        DQ -12

    NEWVARIABLE GREETING
        DB "DATA (C) 2022 DAVID DETWEILER", 10, 10, 0

    NEWHEADER "TRUE"
    NEWCONSTANT TRUE
        DQ 0ffffffffffffffffh

    NEWTHREAD WALK
        DQ COPY ; ( head -- head head )
        DQ BRANCH ; ( head head -- head )
        DQ 2
        DQ DROP ; ( head -- )
        DQ RETURN ; ( -- )
        DQ COPY ; ( head -- head head )
        DQ PRINTNAME ; ( head head -- head )
        DQ PEEK ; ( head -- head.next )
        DQ JUMP
        DQ -10

    NEWTHREAD PRINTNAME
        DQ CELLSIZE
        DQ SUM
        DQ PRINTLINE
        DQ RETURN

    NEWCONSTANT CELLSIZE
        DQ 8
RDATA ENDS

DATA SEGMENT ALIAS(".data") 'DATA'
        REPEAT 64
            DQ 0
        ENDM
    DSTACK:

        REPEAT 64
            DQ 0
        ENDM
    RSTACK:

    NEWVARIABLE STDOUT
        DQ 0

    NEWVARIABLE STDIN
        DQ 0

    NEWVARIABLE LINEBUFFER
        REPEAT 128
            DB 0
        ENDM

    NEWVARIABLE IOPOINTER
        DQ 0

    NEWVARIABLE FILLED
        DQ 1

    NEWVARIABLE ISFRESHLINE
        DQ 0

    NEWVARIABLE TOKENBUFFER
        REPEAT 64
            DB 0
        ENDM

    NEWVARIABLE TOKENPOINTER
        DQ 0
DATA ENDS

DICTIONARY = LATEST

END
