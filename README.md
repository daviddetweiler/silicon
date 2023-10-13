# Silicon

A thrown-together interpreter for a threaded interpretive language. To build this repo, open an x64 VS Developer
Command Prompt, and add a `nasm` binary to the path (this repo is currently built with 2.16.01). Run `nmake` to
build the binary.

## A note on antivirus software

I can't presume to know why, but a recurring issue has been that Windows Defender (and many other AV vendors on
[VirusTotal](https://www.virustotal.com), currently **7**) views the built binary as malicious. Perhaps it has to do with the
inherently obfuscated nature of a threaded interpreter. If you're here to try it out, feel free to read through the
source code to convince yourself it isn't malware.
