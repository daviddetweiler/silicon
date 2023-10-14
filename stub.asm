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
extern GetLastError
extern VirtualProtect

%macro next_bit 0
    cmp r14, r12
    je %%end
    mov rax, r14
    and rax, 64 - 1
    jnz %%bit
    mov r15, [r13]
    add r13, 8

    %%bit:
    bt r15, r14
    setc al
    movzx rax, al
    inc r14
    jmp %%after

    %%end:
    mov rax, -1

    %%after:
%endmacro

%define mask (1 << 9) - 1

section .text
    start:
        mov rbp, rsp
        sub rsp, 8 * 9 + 8 * 16

        mov rcx, 0x2000000000
        mov edx, [blob]
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x04 ; PAGE_READWRITE
        call VirtualAlloc

        mov rcx, 0x2000000000
        mov edx, [blob]
        mov r8, 0x40 ; PAGE_EXECUTE_READWRITE
        lea r9, [rsp + 8 * 4]
        call VirtualProtect

        mov cx, [blob + 4]
        mov dx, cx
        shl cx, 2
        sub cx, dx
        movzx rcx, cx
        lea rdx, blob
        lea rdx, [rdx + rcx + 6]
        mov r12d, [rdx] ; r12 is the bit-length of the compressed data
        lea r13, [rdx + 4] ; r13 points to the compressed data
        xor r14, r14 ; r14 is the bit-index of the compressed data within r15
        lea rsi, [blob + 6] ; rsi is the huffman tree pointer
        mov rdi, 0x2000000000 ; rdi points to the output buffer
        xor rcx, rcx ; rcx is the huffman node index

        .again:
        next_bit
        cmp rax, -1
        je .stream_end

        mov rdx, rcx
        shl rdx, 1
        add rcx, rdx
        mov rdx, [rsi + rcx] ; rdx now holds the huffman node
        and rdx, (1 << 24) - 1 ; but only 24 bits are valid
        mov r8, rdx ; a copy will be used later

        test rax, rax
        jnz .one
        shr rdx, 9

        .one:
        and rdx, mask
        mov rcx, rdx

        bt r8, 23
        jc .not_leaf
        mov [rdi], r8b
        add rdi, 1
        xor rcx, rcx
        dec r14 ; Not sure where the off-by-one comes from but oh well

        .not_leaf:
        jmp .again

        .stream_end:
        xor rcx, rcx
        call ExitProcess

    blob:
        %include "blob.inc"
        align 8 ; We rely on this in next_bit
