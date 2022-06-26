# Silicon

If you'd like to know more about what exactly this project is, read the book "Threaded Interpretive Languages," which
makes by far the best exposition of this style of language. This is my own take on the concept; in particular, no native
subroutines are used: the entire kernel is either the inner interpreter and its bootstrap, or threaded code (including
machine code words). Also of note is that all words are in the dictionary by default, with their full, internal names.

If your familiar with the quote about the "Maxwell's Equations of software," I'm afraid I have to disagree. My version
(at least in x64 assembly) would be this:
```
; Runs the word referenced at the current IP, advances IP
continue:
    mov r13, [r12]
    add r12, 8

; Runs a word, setting WA to point to the data field
run:
    add r13, 8
    jmp qword [r13 - 8]
```

## Building

You will need to open a Visual Studio x64 developer command prompt, and also add [NASM](https://nasm.us) to your `PATH`.
Then just run `nmake`. `nmake run` will run `silicon.exe` in its own console (assuming you have
[Windows Terminal](https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701) installed).
