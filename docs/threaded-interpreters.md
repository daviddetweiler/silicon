# Threaded Interpreters

Threaded interpreters are a family of highly extensible, stack-oriented, concatenative languages that support a
particularly simple implementation. The core of a threaded interpreter is traditionally the ITC execution model, the
virtual machine that affords them their high degree of composability and extensibility. In an ITC engine, a program is
ultimately composed of two types of data: words, and threads (though the terminology varies). A thread is merely an
array of pointers to words, while a word is a variable-length data structure whose only fixed element is the presence of
an initial pointer to machine code. Conceptually, a word associates an action (implemented by this machine code) with
data to be operated upon (the rest of the word after the pointer), essentially a stateful subroutine.

To interpret a thread is extremely simple: the interpreter must advance through the thread, one pointer at a time,
jumping to the machine code referenced by each word in turn. The only contract required of the machine code actions is
to re-invoke the interpreter once they have completed. Since this interpreter is usually extremely short (only a few
instructions), and a shared implementation tends to upset the branch predictor on modern architectures, the interpreter
is inlined at the end of each machine code action. In `Silicon`, the entirety of this "inner interpreter" lives in the
macros `next` and `run`, which together form the following machine code:

    mov wp, [tp]
    add tp, 8
    jmp [wp]

`wp` and `tp` are simply macro aliases for processor registers (specifically `r14` and `r15`, as these are nonvolatile
in the Windows ABI): `tp` points to the current place in the thread, while `wp` points to the current word being
executed. A word's machine code can then access its data area through `wp`.
