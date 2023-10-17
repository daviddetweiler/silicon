default rel
bits 64

%define id_mask (1 << 9) - 1
%define node_mask (1 << 24) - 1
%define leaf_bit (1 << 23)
%define image_base 0x2000000000

%define blob_uncompressed_size blob + 0
%define blob_bit_count blob + 4
%define blob_stream blob + 8

section .text
    start:
        sub rsp, 8 + 8 * 4
        mov rax, rcx

        mov rcx, image_base
        mov edx, [blob_uncompressed_size]
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call rax
        mov rdi, rax ; rdi has the decompression buffer

        mov r12d, [blob_bit_count] ; r12 is the bitstream length in bits
        mov rbx, r12
        and rbx, 7
        mov r9, 8
        sub r9, rbx
        and r9, 7
        add r9, r12
        shr r9, 3 ; r9 now has the number of bitstream bytes

        lea rsi, blob_stream ; rsi is the bitstream pointer
        xor r13, r13 ; r13 is the bitstream index, r14 will hold the current 8-byte stretch of bitstream
        xor r15, r15 ; r15 is the current node index

        add r9, rsi ; r9 now points to the tree data
        movzx rbx, byte [r9] ; bitfield length in bytes
        inc r9 ; bitfield ptr
        add rbx, r9 ; nodes ptr

        .again:
        cmp r13, r12
        je .stream_end
        test r13, 64 - 1
        jnz .valid_bits
        lodsq
        mov r14, rax

        .valid_bits:
        mov rcx, r15
        shl rcx, 1 ; bitpair index (also node index)
        mov r8, rcx ; stashing the node index
        mov rdx, rcx
        shr rdx, 3 ; bitpair byte index
        and rcx, 7 ; bitpair bit index
        movzx rdx, byte [r9 + rdx]
        shr rdx, cl ; rdx now has the bitpair at the bottom

        bt r14, r13
        jc .skip_adjust
        shr rdx, 1
        inc r8

        .skip_adjust:
        movzx rax, byte [rbx + r8] ; node data
        test rdx, 1
        jz .nonleaf
        stosb
        xor rax, rax

        .nonleaf:
        mov r15, rax
        inc r13
        jmp .again

        .stream_end:
        mov rax, image_base + 8
        add rsp, 8 + 8 * 4
        ret

    align 8
    blob:
        %include "compressed.inc"
