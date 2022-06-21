# Silicon

A Forth implementation for Windows, written in MASM64. Currently, only the token-based REPL is complete; it will
tokenize an input line by whitespace and print each token on its own line. Pressing `Ctrl+Z`, `Enter` on its own line
will exit the REPL.

## Building

In an x64 Visual Studio developer command prompt:

    > ML64 .\silicon.asm /link kernel32.lib /fixed /entry:START /subsystem:console
