# Silicon

`Silicon` is a self-decompressing "threaded interpreter" for x64 Windows PCs. Refer to the `docs` subdirectory for more
detailed explanations on the concepts used.

## Build Instructions

You will need a command prompt or `Powershell` session with the x64 Visual Studio developer tools and `NASM` 2.16.01 or
greater on its `PATH`. Running `nmake` will build `silicon.exe` (the compressed binary) and `silicon-debug.exe` (an
uncompressed version with symbols).

## A note on antivirus software

The built binary is a compressed blob stuffed into an otherwise tiny executable. As such, its byte-wise entropy is well
north of the magical `7.2` and currently 10 different AV vendors on [this](https://virustotal.com/) site flag the file
as malicious.
