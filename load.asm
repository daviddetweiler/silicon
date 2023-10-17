default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define image_base 0x2000000000

%define blob_uncompressed_size blob + 0
%define blob_triplet_count blob + 4
%define blob_stream blob + 8

%define dict_size (8 * 2) * 4096

section .text
    start:
        sub rsp, 8 + 8 * 16

        mov rcx, image_base - dict_size
        mov edx, [blob_uncompressed_size]
        add rdx, dict_size
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc

        lea rsi, blob_stream
        mov rdi, image_base ; decompression buffer
        mov r12d, [blob_triplet_count]
        mov r13, image_base - dict_size ; dictionary base

        .again:
        test rdi, 1
        jnz .odd
        mov r14, [rsi]
        add rsi, 3

        .odd:
        mov rax, r14
        and rax, 0xfff

        shr r14, 12
        inc rdi
        dec r12
        jnz .again

        int3
        mov rax, image_base + 8
        lea rcx, GetModuleHandleA
        lea rdx, GetProcAddress
        jmp rax
    
    blob:
        %include "lzw.inc"
