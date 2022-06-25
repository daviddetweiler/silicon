# Silicon

An ANSI Forth implementation for Windows, written in MASM64. Pressing `Ctrl+Z`,
`Enter` on its own line will exit the REPL. Try:

    > cat sample.fth | .\silicon.exe

## Building

In an x64 Visual Studio developer command prompt:

    > ml64 .\silicon.asm /link kernel32.lib /fixed /entry:start /subsystem:console
