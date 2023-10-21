import sys
import math
import ac


def encode_15bit(n):
    assert 0 <= n < 2**15
    if n < 0x80:
        return n.to_bytes(1, "little")
    else:
        hi = n >> 8
        lo = n & 0xFF
        return (0x80 | hi).to_bytes(1, "little") + lo.to_bytes(1, "little")


def lzss_compress(data):
    window = 2**15
    i = 0
    bits = []
    coded = [b"", b"", b""]
    while i < len(data):
        j = 3  # At least 4 bytes are needed to lzss_compress a match, so we match only 5 bytes or more.
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


def entropy(symbols):
    histogram = {}
    for symbol in symbols:
        histogram[symbol] = histogram.get(symbol, 0) + 1

    total = sum(histogram.values())
    probabilities = [histogram[symbol] / total for symbol in histogram]
    return sum(-p * math.log2(p) for p in probabilities)


def encode(lzss, allocation_size):
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

    command_entropy_limit = entropy(lzss[0]) / 1  # 1 bit per command
    literal_entropy_limit = entropy(lzss[1][0]) / 8  # 8 bits per byte
    offset_entropy_limit = entropy(lzss[1][1]) / 8  # 8 bits per byte
    length_entropy_limit = entropy(lzss[1][2]) / 8  # 8 bits per byte

    print(
        f"{command_entropy_limit:.4f} bits per command minimum ({command_entropy_limit * len(lzss[0]) / 8:.0f} bytes)"
    )

    print(
        f"{literal_entropy_limit:.4f} bytes per literal minimum ({literal_entropy_limit * len(lzss[1][0]):.0f} bytes)"
    )

    print(
        f"{offset_entropy_limit:.4f} bytes per offset minimum ({offset_entropy_limit * len(lzss[1][1]):.0f} bytes)"
    )

    print(
        f"{length_entropy_limit:.4f} bytes per length minimum ({length_entropy_limit * len(lzss[1][2]):.0f} bytes)"
    )

    encoder = ac.Encoder()
    command_model = ac.uniform_model(2)
    literal_model = ac.uniform_model(256)
    offset_model = ac.uniform_model(256)
    length_model = ac.uniform_model(256)

    commands = lzss[0]
    literals = lzss[1][0]
    offsets = lzss[1][1]
    lengths = lzss[1][2]
    a, b, c = 0, 0, 0
    encoder.encode_incremental(literal_model, allocation_size.to_bytes(4, "little"))
    encoder.encode_incremental(literal_model, len(commands).to_bytes(4, "little"))
    for bit in commands:
        encoder.encode_incremental(command_model, [bit])
        if bit == 0:
            encoder.encode_incremental(literal_model, literals[a : a + 1])
            a += 1
        else:
            if offsets[b] & 0x80 == 0:
                encoder.encode_incremental(offset_model, offsets[b : b + 1])
                b += 1
            else:
                encoder.encode_incremental(offset_model, offsets[b : b + 2])
                b += 2

            if lengths[c] & 0x80 == 0:
                encoder.encode_incremental(length_model, lengths[c : c + 1])
                c += 1
            else:
                encoder.encode_incremental(length_model, lengths[c : c + 2])
                c += 2

    assert a == len(literals)
    assert b == len(offsets)
    assert c == len(lengths)
    coded = encoder.finalize()
    print(len(coded), "bytes")

    return coded

def decode(encoded):
    decoder = ac.Decoder(encoded)
    command_model = ac.uniform_model(2)
    literal_model = ac.uniform_model(256)
    offset_model = ac.uniform_model(256)
    length_model = ac.uniform_model(256)

    allocation_size = int.from_bytes(bytes(decoder.decode_incremental(literal_model, 4)), "little")
    n_commands = int.from_bytes(bytes(decoder.decode_incremental(literal_model, 4)), "little")

    commands = []
    literals = b""
    offsets = b""
    lengths = b""
    for _ in range(n_commands):
        bit = decoder.decode_incremental(command_model, 1)[0]
        commands.append(bit)
        if bit == 0:
            literals += bytes(decoder.decode_incremental(literal_model, 1))
        else:
            offset_fb = decoder.decode_incremental(offset_model, 1)
            if offset_fb[0] & 0x80 == 0:
                offsets += bytes(offset_fb)
            else:
                offsets += bytes(offset_fb + decoder.decode_incremental(offset_model, 1))

            length_fb = decoder.decode_incremental(length_model, 1)
            if length_fb[0] & 0x80 == 0:
                lengths += bytes(length_fb)
            else:
                lengths += bytes(length_fb + decoder.decode_incremental(length_model, 1))

    lzss = commands, (literals, offsets, lengths)
    print(f"Recovered {len(literals)} bytes of literals")
    print(f"Recovered {len(offsets)} bytes of offsets")
    print(f"Recovered {len(lengths)} bytes of lengths")

    return lzss, allocation_size


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: lzss.py <input> <output>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    lzss = lzss_compress(data)
    encoded = encode(lzss, len(data))
    print("Final compression ratio:", len(encoded) / len(data))

    decode(encoded)

    with open(sys.argv[2], "wb") as f:
        f.write(encoded)
