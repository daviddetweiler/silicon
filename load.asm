default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%include "chksum.inc"

section .text
    start:
        sub rsp, 8 + 8 * 4

        mov r12, (end - image) / 4
        mov r13, seed
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
        lea rcx, GetModuleHandleA
        lea rdx, GetProcAddress
        call r15

    align 16
    image:
        %include "coded.inc"

    end:
