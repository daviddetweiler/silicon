default rel
bits 64

global start

%define image_base 0x2000000000

%define blob_uncompressed_size (blob + 0)
%define blob_stream (blob + 4)

%define dict_size (8 * 2) * 4096

%define next_code rsp + 0
%define prev_ptr rsp + 8
%define prev_len rsp + 16
%define triplet_id rsp + 24

section .text
    start:
        ; This can be wrapped into a call for deduplication
        mov rcx, image_base - dict_size - 256
        mov edx, [blob_uncompressed_size]
        add rdx, dict_size
        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call rax

    blob:
        %include "lzss.inc"

    end:
