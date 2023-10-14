default rel
bits 64

global start

extern ExitProcess
extern GetStdHandle
extern WriteFile
extern ReadFile
extern CreateFileA
extern SetFilePointer
extern CloseHandle
extern VirtualAlloc
extern VirtualFree
extern VirtualProtect

%include "chksum.inc"

section .text
    start:
        sub rsp, 8 + 8 * 4

        lea rcx, image
        mov rdx, end - start
        mov r8, 0x40 ; PAGE_EXECUTE_READWRITE
        lea r9, [rsp + 8 * 4]
        call VirtualProtect

        mov r12, (end - image) / 4
        mov r13, [seed_addr]
        mov r14, image
        xor r15, r15
        
        .again:
        xor [r14 + r15 * 4], r13d
        mov eax, r13d
        shl eax, 13
        xor r13d, eax
        mov eax, r13d
        shr eax, 17
        xor r13d, eax
        mov eax, r13d
        shl eax, 5
        xor r13d, eax
        inc r15
        cmp r15, r12
        jne .again

        lea rcx, VirtualAlloc
        call image
        mov r15, rax
        lea rcx, table
        call r15

    seed_addr:
        dd seed

    align 8
    table:
        dq ExitProcess
        dq GetStdHandle
        dq WriteFile
        dq ReadFile
        dq CreateFileA
        dq SetFilePointer
        dq CloseHandle
        dq VirtualAlloc
        dq VirtualFree

    align 16
    image:
        %include "coded.inc"

    end:
