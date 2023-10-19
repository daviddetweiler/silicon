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

%define codebook_size (8 * 2) * 256

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
        xor r11, r11 ; r11 will be the minimum code length

        .next_find_length:
        xor rcx, rcx ; rcx will be the packed index (i.e. the byte value)

        .next_find:
        cmp [r13 + rcx], al
        jne .next_code
        test r11, r11
        cmovz r11, rax ; if min_length is not set yet, set it
        lea r10, [rcx * 2]
        mov [r12 + r10 * 8], rbx ; store the reconstructed code
        mov [r12 + r10 * 8 + 8], rax ; store the code length
        inc rbx
        .next_code:
        inc rcx
        test rcx, 256 - 1
        jnz .next_find
        shl rbx, 1
        inc rax
        test rax, 64
        jz .next_find_length
        
    decode:
        xor rax, rax ; rax is the bit index
        xor rdx, rdx ; rdx is the number of bytes decoded

        .decode_next_byte:
        xor rbx, rbx ; rbx is the current prefix (the prospective code)
        xor rcx, rcx ; rcx is the current code length (to determine validity)
        
        .decode_next_bit:
        mov r8, rax
        shr r8, 4 ; r8 is the word index
        mov r9, rax
        and r9, 16 - 1 ; rbx is the bit index
        bt word [r15 + r8 * 2], r9w ; check if the bit is set
        setc r8b ; r8b is the bit value
        inc rax ; increment the bit index
        inc rcx ; increment the code length
        shl rbx, 1 ; shift the prefix
        or bl, r8b ; set the bit

        ; not yet enough bits to start cheching for a match
        cmp rcx, r11
        jl .decode_next_bit

        xor r13, r13 ; r13 is the current index into the codebook (for searches)

        .try_next_code:
        lea r10, [r13 * 2]
        cmp rbx, [r12 + r10 * 8]
        jne .next_code
        cmp rcx, [r12 + r10 * 8 + 8]
        jne .next_code
        mov [r14 + rdx], r13b
        inc rdx
        jmp .byte_decoded
        
        .next_code:
        inc r13
        and r13, 256 - 1
        jnz .try_next_code

        ; By here we've tried all 256 codes and none of them matched.
        ; Therefore, we pull in the next bit and try again.
        jmp .decode_next_bit

        .byte_decoded:
        cmp dx, [blob_uncompressed_size]
        jne .decode_next_byte 

    load:
        mov rax, VirtualAlloc
        call r14 ; call stage 2
        mov rcx, GetModuleHandleA
        mov rdx, GetProcAddress
        jmp rax ; invoke final decompressed image

    blob:
        %include "lzss-huff.inc"
