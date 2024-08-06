default rel
bits 64

global start

extern VirtualAlloc
extern GetModuleHandleA
extern GetProcAddress

%define node_size (2 * 8 + 2 * 8 + 8) ; Children, counts, total_count
%define total_nodes (1023) ; Magic number, but known from the python implementation

section .text
    start:
        sub rsp, 8 + 8 * 16

    init_models:
        ; r15 will be the node arena pointer
        mov r15, (total_nodes * node_size)
        xor rcx, rcx
        mov rdx, r15
        call allocate
        add r15, rax

        mov r14, r15 ; root node
        call make_node

        mov r13, r15 ; dummy node
        mov [r13 + 8], r13
        mov [r13], r13
        call make_node

        mov rsi, r14
        call make_15bit_model ; length model in rsi
        call make_15bit_model ; offset model in rsi
        mov rdi, rsi ; dict entry model in rdi

        mov rsi, r15
        mov rcx, r14
        mov rdx, 8
        call make_bitstring ; rsi now points to the literal model

        mov [r15], rsi
        mov rsi, r15 ; rsi now points to the packet model
        mov [r15 + 8], rdi
        call make_node

    make_15bit_model:
        mov rcx, rsi
        mov rsi, r15
        mov rdx, 7
        call make_bitstring ; rsi now points to the short_length model

        mov rdi, r15
        mov rcx, rsi
        mov rdx, 8
        call make_bitstring ; rdi now points to the ext_length model

        mov [r15], rsi
        mov rsi, r15 ; rsi now points to the length model
        mov [r15 + 8], rdi
        call make_node

        ret
    
    allocate:
        sub rsp, 8 + 8 * 4

        mov r8, 0x1000 | 0x2000 ; MEM_COMMIT | MEM_RESERVE
        mov r9, 0x40 ; PAGE_EXECUTE_READWRITE
        call VirtualAlloc

        add rsp, 8 + 8 * 4
        ret

    make_node:
        xor rax, rax
        inc rax
        mov [r15 + 8 * 2], rax
        mov [r15 + 8 * 3], rax
        inc rax
        mov [r15 + 8 * 4], rax
        add r15, node_size
        ret

    ; rcx = root, rdx = bits
    make_bitstring:
        test rdx, rdx
        jnz .recurse
        mov rax, rcx
        ret

        .recurse:
        dec rdx
        call make_bitstring
        mov [r15 + 8], rax
        call make_bitstring
        mov [r15], rax
        inc rdx
        call make_node
        ret

    bitstream:
    %warning %eval(bitstream - start)
