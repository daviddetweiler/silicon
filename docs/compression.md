# A discussion on compression algorithms

`Silicon` employs an `LZ77` pre-pass that aggressively removes substring repetitions in the uncompressed data,
ultimately producing four statistically distinct streams of data: a sequence of control bits, a sequence of data from
the original uncompressed bytes, a sequence of bytes representing offsets, and a sequence of bytes representing lengths.
These are interleaved in a deterministic fashion by an arithmetic coder that models each stream separately, ultimately
outputting a single, compressed bit-stream. The implementation of the compression algorithm is in `bitweaver.py`, with
an assembly-language decoder in `bw.asm`.

## LZ77

## Arithmetic Coding
