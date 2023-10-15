default rel
bits 64

%define id_mask (1 << 9) - 1
%define node_mask (1 << 24) - 1
%define leaf_bit (1 << 23)
%define image_base 0x2000000000

%define blob_uncompressed_size blob + 0
%define blob_bits blob + 4
%define blob_tree_size blob + 8
%define blob_tree blob + 10

section .text
    sub rsp, 8 + 8 * 4

    mov rax, rcx
    mov rcx, image_base
    mov edx, [blob_uncompressed_size]
    mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
    mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
    call rax

    mov cx, [blob_tree_size]
    mov dx, cx
    shl cx, 1
    add cx, dx
    movzx rcx, cx
    lea rdx, blob
    lea rdx, [rdx + rcx + 10]
    
    mov rax, rdx
    and rax, 7
    mov rbx, 8
    sub rbx, rax
    and rbx, 7
    add rdx, rbx

    mov r12d, [blob_bits] ; r12 is the bit-length of the compressed data
    mov r13, rdx ; r13 points to the compressed data
    xor r14, r14 ; r14 is the bit-index into the compressed data
    lea rsi, blob_tree ; rsi is the huffman tree pointer
    mov rdi, image_base ; rdi points to the output buffer
    xor rcx, rcx ; rcx is the huffman node index

    .again:
    cmp r14, r12
    jge .stream_end

    test r14, 64 - 1
    jnz .bits_left
    mov r15, [r13]
    add r13, 8

    .bits_left:
    bt r15, r14
    setc al
    movzx rax, al

    imul rdx, rcx, 3
    add rdx, rsi
    mov rdx, [rdx]
    and rdx, node_mask

    test rax, rax
    jnz .no_adjust
    shr rdx, 9

    .no_adjust:
    mov rcx, rdx
    and rcx, id_mask
    inc r14

    imul rdx, rcx, 3
    add rdx, rsi
    mov rdx, [rdx]
    and rdx, node_mask

    test rdx, leaf_bit
    jnz .not_leaf
    mov [rdi], dl
    add rdi, 1
    xor rcx, rcx

    .not_leaf:
    jmp .again

    .stream_end:
    mov rax, image_base + 8 * 2
    add rsp, 8 + 8 * 4
    ret

    align 8
    blob:
        %include "blob.inc"
