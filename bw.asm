default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define image_base 0x2000000000

section .text
    start:
        sub rsp, 8 + 8 * 16 ; It's what the interpreter expects

    load:
        mov rcx, GetModuleHandleA
        mov rdx, GetProcAddress
        mov rax, image_base
        jmp rax

    image:
        %include "bw.inc"
