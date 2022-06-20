PUBLIC START

EXTERN ExitProcess: PROC
EXTERN GetStdHandle: PROC
EXTERN WriteFile: PROC

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
    DQ LITERAL
    DB "H"
    ALIGN 8
    DQ PUT
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
    MOV QWORD PTR [RSP+32], 0
    CALL WriteFile
    ADD R15, 16
    JMP CONTINUE
    ALIGN 8

DOVAR:
    SUB R15, 8
    MOV [R15], R13
    JMP CONTINUE
    ALIGN 8

STDOUT:
    DQ DOVAR
    DQ 0

STDIN:
    DQ DOVAR
    DQ 0

SILICON ENDS

END
