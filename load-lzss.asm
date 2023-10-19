default rel
bits 64

global start

%define image_base 0x2000000000

%define blob_uncompressed_size (blob + 4)
%define blob_bitfield_bytes (blob + 6)
%define blob_bitfield (blob + 8)

%define dict_size (8 * 2) * 4096

%define next_code rsp + 0
%define prev_ptr rsp + 8
%define prev_len rsp + 16
%define triplet_id rsp + 24

section .text
    start:
        sub rsp, 8 + 8 * 4

        lea r14, blob_bitfield ; r14 keeps the bitfield
        movzx r12, word [r14 - 4] ; r12 keeps the decompressed size

        ; This can be wrapped into a call for deduplication
        mov rcx, image_base
        mov edx, dword [r14 - 8]
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

        call decode_15bit
        mov rbx, rax ; rbx keeps the offset
        call decode_15bit ; rcx keeps the length
        mov rcx, rax
        neg rbx ; rbx was a backwards offset, so we negate it to get the true relative offset
        sub r12, rcx ; r12 keeps the remaining bytes to decode

        .next_copy:
        mov rax, [rdi + rbx]
        stosb
        dec rcx
        jnz .next_copy

        ; r13 was already adjusted by decode_15bit
        inc r15
        test r12, r12
        jnz .next_command

        mov rax, image_base + 8
        add rsp, 8 + 8 * 4
        ret

        .literal:
        movzx rax, byte [r13]
        stosb
        inc r13
        inc r15
        dec r12
        jnz .next_command

    ; r13 keeps the compressed stream
    decode_15bit:
        movzx r10, byte [r13]
        test r10, 0x80
        jnz .long
        mov rax, r10
        inc r13
        ret

        .long:
        mov rax, r10
        and rax, 0x7f
        shl rax, 8
        movzx r10, byte [r13 + 1]
        or rax, r10
        add r13, 2
        ret

    blob:
        %include "lzss.inc"
