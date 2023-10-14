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

%define id_mask (1 << 9) - 1
%define node_mask (1 << 24) - 1
%define leaf_bit (1 << 23)
%define image_base 0x2000000000

section .text
    start:
        mov rbp, rsp
        sub rsp, 8 * 9

        mov rcx, image_base
        mov edx, [blob]
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc

        mov cx, [blob + 4]
        mov dx, cx
        shl cx, 2
        sub cx, dx
        movzx rcx, cx
        lea rdx, blob
        lea rdx, [rdx + rcx + 6]
        mov r12d, [rdx] ; r12 is the bit-length of the compressed data
        lea r13, [rdx + 4] ; r13 points to the compressed data
        xor r14, r14 ; r14 is the bit-index into the compressed data
        lea rsi, [blob + 6] ; rsi is the huffman tree pointer
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
        lea rax, ExitProcess
        mov [rsp], rax
        lea rax, GetStdHandle
        mov [rsp + 8 * 1], rax
        lea rax, WriteFile
        mov [rsp + 8 * 2], rax
        lea rax, ReadFile
        mov [rsp + 8 * 3], rax
        lea rax, CreateFileA
        mov [rsp + 8 * 4], rax
        lea rax, SetFilePointer
        mov [rsp + 8 * 5], rax
        lea rax, CloseHandle
        mov [rsp + 8 * 6], rax
        lea rax, VirtualAlloc
        mov [rsp + 8 * 7], rax
        lea rax, VirtualFree
        mov [rsp + 8 * 8], rax

        mov rax, image_base + 8 * 2
        mov rcx, rsp
        call rax

        xor rcx, rcx
        call ExitProcess

    blob:
        %include "blob.inc"
        align 8 ; We rely on this when extracting bits from the compressed data
