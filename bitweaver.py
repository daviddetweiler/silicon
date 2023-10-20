import sys
import math


def encode_15bit(n):
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "little")
    else:
        hi = n >> 8
        lo = n & 0xFF
        return (0x80 | hi).to_bytes(1, "little") + lo.to_bytes(1, "little")


def encode(data):
    window = 2**15
    i = 0
    bits = []
    coded = [b"", b"", b""]
    while i < len(data):
        j = 3  # At least 4 bytes are needed to encode a match, so we match only 5 bytes or more.
        longest_match = None
        while True:
            window_base = max(0, i - window)
            window_data = data[window_base : i + j - 1]
            m = window_data.rfind(data[i : i + j])
            if m == -1 or i + j > len(data) or j >= window:
                break
            else:
                longest_match = i - (window_base + m), j
                j += 1

        if longest_match is not None:
            offset, length = longest_match
            offset_code = encode_15bit(offset)
            length_code = encode_15bit(length)
            if len(offset_code) + len(length_code) < length:
                coded[1] += offset_code
                coded[2] += length_code
                bits.append(1)
                i += length
            else:
                coded[0] += data[i].to_bytes(1, "little")
                bits.append(0)
                i += 1
        else:
            coded[0] += data[i].to_bytes(1, "little")
            bits.append(0)
            i += 1

    return bits, coded


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: lzss.py <input> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    lzss = encode(data)
    print(len(lzss[0]), "bits")
    print(len(lzss[1][0]), "bytes of literals")
    print(len(lzss[1][1]), "bytes of offsets")
    print(len(lzss[1][2]), "bytes of lengths")
    print(
        len(lzss[1][0])
        + len(lzss[1][1])
        + len(lzss[1][2])
        + math.ceil(len(lzss[0]) / 8),
        "bytes total",
    )
