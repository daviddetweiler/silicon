default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define image_base 0x2000000000

%define blob_uncompressed_size (blob + 0)
%define blob_codebook (blob + 2)
%define blob_stream (blob + 2 + 256)

%define codebook_size 8 * 256

section .text
    start:
        sub rsp, 8 + 8 * 16

        xor rcx, rcx
        movzx rdx, word [blob_uncompressed_size]
        add rdx, codebook_size
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc

        mov r12, rax ; unpacked codebook
        lea r13, blob_codebook ; packed codebook
        lea r14, [r12 + codebook_size] ; unpacked stream
        lea r15, blob_stream ; packed stream

    reconstruct_codebook:
        xor rax, rax
        inc rax ; rax will be the current code length
        xor rbx, rbx ; rbx will be the current code bits

        .next_find_length:
        xor rcx, rcx ; rcx will be the packed index (i.e. the byte value)

        .next_find:
        cmp [r13 + rcx], al
        jne .next_code
        mov [r12 + rcx * 8], rbx ; store the reconstructed code
        inc rbx
        .next_code:
        inc rcx
        test rcx, 256 - 1
        jnz .next_find
        shl rbx, 1
        inc rax
        test rax, 64
        jz .next_find_length
        
        int3
        mov rcx, VirtualAlloc
        call r14 ; call stage 2
        jmp rax ; invoke final decompressed image

    align 4
    blob:
        %include "lzss-huff.inc"

    end:
