PUBLIC START

EXTERN ExitProcess: PROC

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
    DQ EXIT

SILICON ENDS

END
