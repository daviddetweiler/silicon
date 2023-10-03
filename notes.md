I have a handful of projects, including a chess-playing bot. Absolutely nothing is stopping me from writing them
entirely in a Forth of my own design, other than the fact that I have never completed any. Yes, it goes against my
not-invented-here puritanism to write _Windows_ software, but think of it this way: I get to control _exactly_ how I'm
using the CPU in user mode. Everything outside of memory and computation (which I get to control fully) I depend
entirely on system calls for. I.e., depend on the OS or external systems as little as humanly possible. This does raise
a chicken-and-egg question when it comes to "should I make a x64 PE encoder or not." Specifically, I'd have to rewrite
the encoder anyway, but there's also the fact that I'd be wrestling with `nasm` and `nmake` until the end of time if I
went the other route.

If the TIL/Forth is to be my Swiss army knife, I want it to be _completely_ mine. Down to instruction encoding and
layout in memory. This does make it certain that I must eventually code a self-hosting variety that can regenerate its
own binary, but this says nothing about the bootstrap version. Do I write the bootstrap version in `nasm` or in my own
PE encoder? Well the self-hosted version is going to completely, verbatim, reimplement whatever it is that I end up
writing in the assembly kernel anyway, so an eye to intellectual purity would encourage that I treat the encoding bits
of the self-hosted version as just another port. That is, that I should treat the encoder as the "original"
meta-compiler (the bootstrap) which generates the interpreter that it will be ported to.

Which means that I have to actually bother cleaning up the `pe_builder::write_to()` method, because it's near
incomprehensible rn.

AFAIK, the PE format logically consists of a number of "sections," and keeps track of their layout both in memory and on
disk. So tape-out requires that I loop over all the sections and determine their layout both in memory _and_ on disk to
even have the information needed to fill in the headers properly. Since we also know, before we've even seen the
sections to be written out, what headers we are going to write (including how many section headers need be written),
this means that we end up precomputing the size and layout of the entire file. So we can just seek to the known end,
write a zero, then backtrack and write-in pieces as needed.
