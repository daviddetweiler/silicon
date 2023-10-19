default rel
bits 64

global start

%define image_base 0x2000000000

%define blob_uncompressed_size (blob + 0)
%define blob_bitfield_bytes (blob + 2)
%define blob_bitfield (blob + 4)

%define dict_size (8 * 2) * 4096

%define next_code rsp + 0
%define prev_ptr rsp + 8
%define prev_len rsp + 16
%define triplet_id rsp + 24

section .text
    start:
        lea r14, blob_bitfield ; r14 keeps the bitfield
        movzx r12, word [r14 - 4] ; r12 keeps the decompressed size

        ; This can be wrapped into a call for deduplication
        mov rcx, image_base
        mov rdx, r12
        add rdx, dict_size
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call rax
        mov rdi, rax ; rdi keeps the decompressed stream
        
        movzx r13, word [r14 - 2]
        add r13, r14 ; r13 keeps the compressed stream
        xor r15, r15 ; r15 is the command index

        .next_command:
        mov rax, r15
        shr rax, 4 ; word address
        mov rbx, r15
        and rbx, 15 ; bit address
        bt word [r14 + rax * 2], bx
        jnc .literal
        int3

        .literal:
        movzx rax, byte [r13]
        stosb
        inc r13
        inc r15
        dec r12
        jnz .next_command

    blob:
        %include "lzss.inc"
