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
%define triplet_id rsp + 24

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
        lea rdx, [rcx - 256] ; single-bytes array
        xor r8, r8

        .next_init:
        mov r9, r8
        shl r9, 4 ; * 16
        lea r9, [r9 + rcx]
        lea rax, [r8 + rdx]
        mov [rax], r8b
        mov [r9], rax
        mov qword [r9 + 8], 1
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
        test qword [triplet_id], 1
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
        jmp .advance

        .no_reset:
        cmp rbx, [next_code]
        jge .no_match

        shl rbx, 4 ; * 16
        add rbx, r13
        mov rcx, [rbx]
        mov rdx, [rbx + 8]
        call write_span

        mov rcx, [prev_ptr]
        mov rdx, [prev_len]
        inc rdx

        ; contains(ptr, len)
        mov r8, [next_code] ; next code
        mov r9, r13 ; dictionary base

        .next_row:
        cmp rdx, [r9 + 8]
        jne .next_entry
        xor r10, r10

        .compare_next:
        mov rax, [r9]
        mov al, [rax + r10]
        cmp al, byte [rcx + r10]
        jne .next_entry
        inc r10
        cmp r10, rdx
        jne .compare_next

        mov rax, 1
        jmp .search_done

        .next_entry:
        add r9, 16 ; sizeof(dict_entry)
        dec r8
        jnz .next_row

        xor rax, rax
        
        ; after contains()
        .search_done:
        test rax, rax
        jnz .contained

        mov rcx, [prev_ptr]
        mov rdx, [prev_len]
        inc rdx
        call write_row

        .contained:
        mov rcx, [prev_len]
        add [prev_ptr], rcx
        mov rax, [rbx + 8]
        mov [prev_len], rax

        jmp .advance

        .no_match:
        mov rcx, [prev_ptr]
        mov rdx, [prev_len]
        call write_span
        mov rax, [prev_ptr]
        mov al, byte [rax]
        mov byte [rdi], al
        inc rdi

        mov rcx, [prev_ptr]
        mov rdx, [prev_len]
        add rcx, rdx
        inc rdx
        mov [prev_ptr], rcx
        mov [prev_len], rdx
        call write_row

        .advance:
        shr r14, 12
        inc qword [triplet_id]
        dec r12
        jnz .again

        mov rax, image_base + 8
        lea rcx, GetModuleHandleA
        lea rdx, GetProcAddress
        jmp rax

    ; write_span(ptr, len)
    write_span:
        test rdx, rdx
        jz .skip

        .again:
        mov al, byte [rcx]
        mov byte [rdi], al
        inc rcx
        inc rdi
        dec rdx
        jnz .again

        .skip:
        ret

    ; write_row(ptr, len)
    write_row:
        mov rax, [8 + next_code]
        inc qword [8 + next_code]
        shl rax, 4 ; * 16
        lea rax, [r13 + rax]
        mov [rax], rcx
        mov [rax + 8], rdx
        ret

    align 8
    blob:
        %include "lzw.inc"
