# Silicon

A Forth implementation for Windows, written in MASM64. Currently, we have a small set of words exposed to the
interpreter, but no literals support. Pressing `Ctrl+Z`, `Enter` on its own line will exit the REPL. Try:

    > cat fancy.f | .\silicon.exe

## Building

In an x64 Visual Studio developer command prompt:

    > ml64 .\silicon.asm /link kernel32.lib /fixed /entry:start /subsystem:console
