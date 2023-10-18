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

%define next_code rsp + 0
%define prev_ptr rsp + 8
%define prev_len rsp + 16

section .text
    start:
        sub rsp, 8 + 8 * 16

        mov rcx, image_base - dict_size - 256
        mov edx, [blob_uncompressed_size]
        add rdx, dict_size
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc

        mov rcx, image_base - dict_size ; dict base
        mov rdx, image_base - dict_size - 256 ; byte array
        xor r8, r8
        
        .next_init:
        mov r9, r8
        shl r9, 4 ; * 16
        lea r9, [r9 + rcx]
        lea rax, [r8 + rdx]
        mov [rax], r8b
        mov [r9], rax
        mov dword [r9 + 8], 1
        xor rax, rax
        crc32 rax, r8b
        mov dword [r9 + 12], eax
        inc r8
        cmp r8, 256
        jne .next_init

        lea rsi, blob_stream
        mov rdi, image_base ; decompression buffer
        mov r12d, [blob_triplet_count]
        mov r13, image_base - dict_size ; dictionary base
        mov qword [next_code], 256
        mov [prev_ptr], rdi
        xor rax, rax
        mov qword [prev_len], rax

        .again:
        test rdi, 1
        jnz .odd
        mov r14, [rsi]
        add rsi, 3

        .odd:
        mov rbx, r14
        and rbx, 0xfff

        cmp rbx, 4095
        jne .no_reset
        mov qword [next_code], 256
        mov [prev_ptr], rdi
        xor rax, rax
        mov qword [prev_len], rax
        int3
        jmp .again

        .no_reset:
        shr r14, 12
        inc rdi
        dec r12
        jnz .again

        int3
        mov rax, image_base + 8
        lea rcx, GetModuleHandleA
        lea rdx, GetProcAddress
        jmp rax

    ; crc_bytes(ptr, len): crc
    crc_bytes:
        xor rax, rax

        .next:
        crc32 rax, byte [rcx]
        inc rcx
        dec rdx
        jnz .next
        ret
    
    blob:
        %include "lzw.inc"
