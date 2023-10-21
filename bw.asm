default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define image_base 0x2000000000

%define literal_model_offset 8
%define offset_model_offset (8 + 256 * 8) + 8
%define length_model_offset 2 * (8 + 256 * 8) + 8
%define control_model_offset 3 * (8 + 256 * 8) + 8
%define models_size 3 * (8 + 256 * 8) + (8 + 2 * 8)

; The first thing the decoder should do is allocate enough memory for all four models used by the arithmetic coder. Each
; bin is 64 bits, we have three 256-symbol models and one 2-symbol model. Thus we need 8 * (3 * 256 + 2) = 6160 bytes.
; Each model also needs the 64-bit total count, so we need 8 * 4 = 32 bytes for that. We can lay them out with the
; literal model first, the offset model, the length model, and finally the control bit model. We can and should use
; subroutines, as we need to allocate at least 5 times (one for each model and once for the image), we need to
; initialize each model the same way (address + symbol count), and we perform n-symbol decodes in several places in the
; LZSS unpacker. We only need at most 4 symbols at a time, so the decoder subroutine should return in a register. As
; arguments it takes the model address, whether it is a 1-bit or 8-bit model, and the number of symbols (up to 4). The
; outermost layer of the decoder is essentially a state machine. We first decode a 4-byte allocation size and
; immediately allocate the decompression buffer. Then we decode a 4-byte LZSS command count, stash it in our state, and
; begin looping. The loop is essentially the decode() function in bitweaver.py.

section .text
    start:
        sub rsp, 8 + 8 * 16 ; It's what the interpreter expects

    init_models:
        xor rcx, rcx
        mov rdx, models_size
        call allocate
        lea r15, [rax + 8] ; r15 = models address

        mov rax, 3
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

        .next_init:
        shl r11, 8
        mov rax, bitstream
        mov r11b, [rax + r10]
        inc r10
        test r10, 7
        jnz .next_init

    prepare_decompression:
        mov rcx, r15 ; use literals model
        mov rdx, 256 ; 8-bit model
        mov r8, 4 ; 4 symbols
        call decode

        mov rcx, image_base
        mov rdx, rax
        call allocate
        mov rdi, rax ; rdi = decompression buffer address

    prepare_lzss_unpack:
        mov rcx, r15
        mov rdx, 256
        mov r8, 4
        call decode
        mov r14, rax ; r14 = command count

    load:
        int3
        mov rcx, GetModuleHandleA
        mov rdx, GetProcAddress
        mov rax, image_base
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

    ; This will perform the arithmetic decode and return the symbols in rax, the first symbol nearest the LSB, so that
    ; little-endian values are already in the correct order.
    decode:
        ret

    bitstream:
        %include "bw.inc"
