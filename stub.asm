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
        xor r14, r14 ; r14 is the bit-index into the compressed data
        lea rsi, [blob + 6] ; rsi is the huffman tree pointer
        mov rdi, 0x2000000000 ; rdi points to the output buffer
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
        and rdx, (1 << 24) - 1

        test rax, rax
        jnz .no_adjust
        shr rdx, 9

        .no_adjust:
        mov rcx, rdx
        and rcx, mask
        inc r14

        imul rdx, rcx, 3
        add rdx, rsi
        mov rdx, [rdx]
        and rdx, (1 << 24) - 1
        
        test rdx, (1 << 23)
        jnz .not_leaf
        mov [rdi], dl
        add rdi, 1
        xor rcx, rcx

        .not_leaf:
        jmp .again

        .stream_end:
        int3
        xor rcx, rcx
        call ExitProcess

    blob:
        %include "blob.inc"
        align 8 ; We rely on this in next_bit
