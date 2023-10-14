# Silicon

A thrown-together interpreter for a threaded interpretive language. To build this repo, open an x64 VS Developer
Command Prompt, and add a `nasm` binary to the path (this repo is currently built with 2.16.01). Run `nmake` to
build the binary.

## A note on antivirus software

The built binary is a compressed blob stuffed into an otherwise tiny executable. As such, it's byte-wise entropy is well
north of the magical `7.2` and currently 10 different AV vendors on [this](https://virustotal.com/) site flag the file
as malicious.
