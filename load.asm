default rel
bits 64

global start

section .text
    start:
    
    blob:
        %include "lzw.inc"
