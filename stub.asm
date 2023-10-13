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
        mov ecx, [rdx + rcx + 6] ; rcx is the bit-length of the compressed data

        xor rcx, rcx
        call ExitProcess

    blob:
        %include "blob.inc"
