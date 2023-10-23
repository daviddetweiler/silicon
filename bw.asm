default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define image_base 0x2000000000

%define model256_size (8 + 256 * 8)
%define model2_size (8 + 2 * 8)
%define model_offset(i) (i * model256_size)

%define literal_model_offset model_offset(0)
%define offset_model_offset model_offset(1)
%define length_model_offset model_offset(2)
%define alt_offset_model_offset model_offset(3)
%define alt_length_model_offset model_offset(4)
%define control_model_offset model_offset(5)
%define models_size control_model_offset + model2_size
%define model256_count 5

; Maybe worth exploring the markov-chain control bit predictor now, with the large file sizes? Could even fit in 8
; KiBs...

section .text
    start:
        sub rsp, 8 + 8 * 16 ; It's what the interpreter expects

    init_models:
        xor rcx, rcx
        mov rdx, models_size
        call allocate
        lea r15, [rax + 8] ; r15 = models address

        mov rax, model256_count
        mov rcx, r15
        .next_model:
        mov rdx, 256
        call init_model
        add rcx, 8 * 256 + 8
        dec rax
        jnz .next_model

        mov rdx, 2
        call init_model

    prepare_decoder:
        xor r13, r13 ; r13 = arithmetic decoder lower bound
        xor r12, r12 ; r12 = arithmetic decoder upper bound
        xor r11, r11 ; r11 = arithmetic decoder 64-bit window
        xor r10, r10 ; r10 = bitstream unconsumed byte index

        not r12 ; set all ones

        .next_init:
        shl r11, 8
        mov rax, bitstream
        mov r11b, [rax + r10]
        inc r10
        test r10, 7
        jnz .next_init

    prepare_decompression:
        call decode_literal_dword

        mov [rsp + 8 * 4], r11
        mov [rsp + 8 * 5], r10

        mov rcx, image_base
        mov edx, eax
        call allocate
        mov rdi, rax ; rdi = decompression buffer address

        mov r11, [rsp + 8 * 4]
        mov r10, [rsp + 8 * 5]

    prepare_lzss_unpack:
        call decode_literal_dword
        mov r14d, eax ; r14 = expected bytes to unpack

    lzss_unpack:
        .next_command:
        lea rcx, [r15 + control_model_offset]
        mov rdx, 2
        mov r8, 1
        call decode

        test al, al
        jz .literal

        .copy_command:
        call decode_offset_byte
        xor rsi, rsi
        mov sil, al

        test rsi, 0x80
        jz .get_length

        xor rsi, 0x80 ; clear the flag
        shl rsi, 8

        call decode_offset_byte
        mov sil, al

        .get_length:
        call decode_length_byte

        shl rsi, 32
        mov sil, al

        test rsi, 0x80
        jz .copy_loop

        xor rsi, 0x80 ; clear the flag
        shl esi, 8

        call decode_length_byte
        mov sil, al

        .copy_loop: ; By now the upper 32 bits of rsi are the offset, and the lower 32 bits are the length
        mov rbx, rsi
        shr rbx, 32
        neg rbx
        mov esi, esi
        sub r14, rsi

        .next_byte:
        mov al, [rdi + rbx]
        stosb
        dec rsi
        jnz .next_byte

        jmp .advance

        .literal:
        call decode_literal_byte
        dec r14
        stosb

        .advance:
        test r14, r14
        jnz .next_command

    load:
        mov rcx, GetModuleHandleA
        mov rdx, GetProcAddress
        mov rax, image_base + 8
        jmp rax

    allocate:
        sub rsp, 8 + 8 * 4

        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc
        
        add rsp, 8 + 8 * 4
        ret

    ; rcx = model address
    ; rdx = model alphabet size
    init_model:
        .next_pvalue:
        inc qword [rcx - 8]
        inc qword [rcx - 8 + rdx * 8]
        dec rdx
        jnz .next_pvalue
        ret

    ; This will perform the arithmetic decode and return the symbols in rax.
    ; WARNING the unwritten bits of rax are undefined, so mask them off before using.
    ; WARNING the symbols are written in reverse order, so you must reverse them before using.
    ; rcx = model address
    ; rdx = model alphabet size
    ; r8 = number of symbols to decode
    ; High register pressure here, r15-r10 in use, as is rdi, rcx, r8, rdx
    decode:
        sub rsp, 8

        mov rbp, rdx ; rbp = model alphabet size

        .next_symbol:
        mov rbx, r12
        sub rbx, r13 ; rbx = interval width

        xor r9, r9 ; r9 = trial symbol

        .next_subinterval:
        mov rdx, [rcx + r9 * 8] ; rdx = symbol frequency
        xor rax, rax
        div qword [rcx - 8] ; rax = symbol probability
        xor rdx, rdx
        mul rbx ; rdx = subinterval width

        add rdx, r13 ; rdx = subinterval lower bound
        cmp rdx, r11 ; range check
        jb .advance_subinterval
        mov r12, rdx ; update upper bound
        mov byte [rsp + r8 - 1], r9b ; store symbol
        inc qword [rcx + r9 * 8] ; update model
        inc qword [rcx - 8] ; update model
        jmp .renormalize

        .advance_subinterval:
        mov r13, rdx ; update lower bound
        inc r9
        cmp r9, rbp
        jne .next_subinterval

        .renormalize:
        mov rbx, r12
        xor rbx, r13 ; any clear bits are the "frozen" bits
        mov rax, ((1 << 8) - 1) << (64 - 8)
        test rbx, rax ; check if we have 8 frozen bits at the top
        jnz .shifting_done
        shl r12, 8 ; renormalize
        not r12b ; set all ones in the lower 8 bits
        shl r13, 8
        shl r11, 8
        mov rax, bitstream
        mov r11b, [rax + r10]
        inc r10
        jmp .renormalize

        .shifting_done:
        dec r8
        jnz .next_symbol
        
        mov rax, qword [rsp] ; rax = decoded symbols
        add rsp, 8
        ret

    decode_length_byte:
        lea rcx, [r15 + length_model_offset]
        mov rdx, 256
        mov r8, 1
        call decode
        ret

    decode_offset_byte:
        lea rcx, [r15 + offset_model_offset]
        mov rdx, 256
        mov r8, 1
        call decode
        ret

    decode_literal_byte:
        lea rcx, [r15 + literal_model_offset]
        mov rdx, 256
        mov r8, 1
        call decode
        ret

    decode_literal_dword:
        lea rcx, [r15 + literal_model_offset]
        mov rdx, 256
        mov r8, 4
        call decode
        bswap eax
        ret

    bitstream:
        %include "bw.inc"
